%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2012-2023 Marc Worrell
%% @doc Manage a resource's revisions.
%% @end

%% Copyright 2012-2023 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(m_backup_revision).

-behaviour(zotonic_model).

-export([
    m_get/3,

    list_deleted/2,

    save_revision/3,
    get_revision/2,
    list_revisions/2,
    list_revisions_assoc/2,

    periodic_cleanup/1,
    retention_months/1,

    install/1
]).

-include_lib("zotonic_core/include/zotonic.hrl").

-define(BACKUP_TYPE_PROPS, $P).

% Number of months we keep revisions
-define(BACKUP_REVISION_RETENTION_MONTHS, 18).


%% @doc Fetch the value for the key from a model source
-spec m_get( list(), zotonic_model:opt_msg(), z:context() ) -> zotonic_model:return().
m_get([ <<"list">>, Id | Rest ], _Msg, Context) ->
    Id1 = m_rsc:rid(Id, Context),
    Revs = case m_rsc:is_editable(Id1, Context) of
        true -> list_revisions_assoc(Id1, Context);
        false -> []
    end,
    {ok, {Revs, Rest}};
m_get([ <<"retention_months">> | Rest ], _Msg, Context) ->
    {ok, {retention_months(Context), Rest}};
m_get(_Vs, _Msg, _Context) ->
    {error, unknown_path}.


-spec list_deleted(OffsetLimit, Context) -> Result when
    OffsetLimit :: {non_neg_integer(), non_neg_integer()},
    Context :: z:context(),
    Result :: #search_result{}.
list_deleted({Offset, Limit}, Context) ->
    {ok, Rs} = z_db:qmap("
        with last_revision as (
            select *
            from backup_revision
            where id in (
                select max(id)
                from backup_revision
                where type = $3
                group by rsc_id
            )
        )
        select rsc_gone.*,
               last_revision.*
        from rsc_gone
        join last_revision
            on rsc_gone.id = last_revision.rsc_id
        order by rsc_gone.created desc, rsc_gone.id desc
        offset $1
        limit $2
        ",
        [ Offset-1, Limit, ?BACKUP_TYPE_PROPS ],
        Context),
    Total = z_db:q1("
        select count(distinct r.id)
        from rsc_gone r
        join backup_revision b
            on r.id = b.rsc_id
            and b.type = $1
        ", [ ?BACKUP_TYPE_PROPS ], Context),
    Rs1 = lists:map(fun expand/1, Rs),
    #search_result{
        result = Rs1,
        total = Total,
        is_total_estimated = false
    }.

expand(#{
        <<"data_type">> := <<"erlang">>,
        <<"data">> := Data
    } = R) ->
    R#{
        <<"data_type">> => <<"term">>,
        <<"data">> => erlang:binary_to_term(Data)
    };
expand(R) ->
    R.


save_revision(Id, #{ <<"version">> := Version } = Props, Context) when is_integer(Id), is_map(Props) ->
    LastVersion = z_db:q1("select version from backup_revision where rsc_id = $1 order by created desc limit 1", [Id], Context),
    case Version of
        LastVersion when LastVersion =/= undefined ->
            ok;
        _ ->
            UserId = z_acl:user(Context),
            1 = z_db:q("
                insert into backup_revision
                    (rsc_id, type, version, user_id, user_name, data_type, data)
                values ($1, $2, $3, $4, $5, $6, $7)
                ", [
                    Id,
                    ?BACKUP_TYPE_PROPS,
                    Version,
                    UserId,
                    z_string:truncate(
                        z_trans:lookup_fallback(
                            m_rsc:p_no_acl(UserId, title, Context),
                            Context),
                        60),
                    <<"erlang">>,
                    erlang:term_to_binary(Props, [compressed])
                ],
                Context),
            ok
    end.


get_revision(RevId0, Context) ->
    RevId = z_convert:to_integer(RevId0),
    case z_db:assoc_row("select * from backup_revision where id = $1", [RevId], Context) of
        undefined ->
            {error, notfound};
        Row ->
            R1 = proplists:delete(data, Row),
            {ok, [ {data, erlang:binary_to_term(proplists:get_value(data, Row)) } | R1 ]}
    end.

list_revisions(undefined, _Context) ->
    [];
list_revisions(Id, Context) when is_integer(Id) ->
    z_db:q("
        select id, type, created, version, user_id, user_name
        from backup_revision
        where rsc_id = $1
        order by created desc", [Id], Context);
list_revisions(Id, Context) ->
    list_revisions(m_rsc:rid(Id, Context), Context).

list_revisions_assoc(undefined, _Context) ->
    [];
list_revisions_assoc(Id, Context) when is_integer(Id) ->
    z_db:assoc("
        select id, type, created, version, user_id, user_name
        from backup_revision
        where rsc_id = $1
        order by created desc", [Id], Context);
list_revisions_assoc(Id, Context) ->
    list_revisions_assoc(m_rsc:rid(Id, Context), Context).


%% @doc Delete revisions older than mod_backup.revision_retention_months, which
%% defaults to 18 months.
-spec periodic_cleanup(Context) -> ok when
    Context :: z:context().
periodic_cleanup(Context) ->
    Months = retention_months(Context),
    Threshold = z_datetime:prev_month(calendar:universal_time(), Months),
    z_db:q("
        delete from backup_revision
        where created < $1",
        [Threshold],
        Context),
    ok.

%% @doc Return the number of months we keep revisions. Defaults to 18 months. Uses
%% the configuration mod_backup.revision_retention_months
-spec retention_months(Context) -> Months when
    Context :: z:context(),
    Months :: pos_integer().
retention_months(Context) ->
    case z_convert:to_integer(m_config:get_value(mod_backup, revision_retention_months, Context)) of
        undefined ->
            ?BACKUP_REVISION_RETENTION_MONTHS;
        N ->
            max(N, 1)
    end.

%% @doc Install the revisions table.
install(Context) ->
    case z_db:table_exists(backup_revision, Context) of
        false ->
            [] = z_db:q("
                    create table backup_revision (
                        id bigserial not null,
                        type character(1) not null,
                        rsc_id integer not null,
                        created timestamp with time zone not null default current_timestamp,
                        version integer,
                        user_id integer,
                        user_name character varying(80),
                        filename character varying(400),
                        note character varying(200),
                        data_type character varying(10) not null,
                        data bytea not null,

                        primary key (id)
                    )
                ", Context),
            [] = z_db:q("
                    create index backup_revision_id_created on backup_revision (rsc_id, created)
                ", Context),
            ok;
        true ->
            ok
    end.
