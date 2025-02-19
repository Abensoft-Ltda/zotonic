%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2010-2011 Marc Worrell
%% Date: 2010-01-15
%%
%% @doc Model for managing the comments on a page.

%% Copyright 2010-2011 Marc Worrell
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

-module(m_comment).
-author("Marc Worrell <marc@worrell.nl").

-behaviour(zotonic_model).

%% interface functions
-export([
    m_get/3,

    list_rsc/2,
    get/2,
    insert/6,
    delete/2,
    is_deletable/2,
    toggle/2,
    gravatar_code/1,
    merge/3,

    search/3
]).

-include_lib("zotonic_core/include/zotonic.hrl").

%% Cache time for comment listings and comment counts.
-define(MAXAGE_COMMENT, 7200).


%% @doc Fetch the value for the key from a model source
-spec m_get( list(), zotonic_model:opt_msg(), z:context() ) -> zotonic_model:return().
m_get([ <<"anonymous">> | Rest ], _Msg, Context) ->
    Anon = case m_config:get_value(mod_comment, anonymous, Context) of
        undefined -> true;
        V -> z_convert:to_bool(V)
    end,
    {ok, {Anon, Rest}};
m_get([ <<"moderate">> | Rest ], _Msg, Context) ->
    Mod = case m_config:get_value(mod_comment, moderate, Context) of
        undefined -> false;
        <<>> -> false;
        V -> z_convert:to_bool(V)
    end,
    {ok, {Mod, Rest}};
m_get([ <<"rsc">>, Id | Rest ], _Msg, Context) ->
    case z_acl:rsc_visible(Id, Context) of
        true -> {ok, {list_rsc(Id, Context), Rest}};
        false -> {error, eacces}
    end;
m_get([ <<"count">>, Id | Rest ], _Msg, Context) ->
    case z_acl:rsc_visible(Id, Context) of
        true -> {ok, {count_rsc(Id, Context), Rest}};
        false -> {error, eacces}
    end;
m_get([ <<"get">>, CommentId | Rest ], _Msg, Context) ->
    case get(CommentId, Context) of
        undefined ->
            {ok, {undefined, Rest}};
        Comment ->
            RscId = proplists:get_value(rsc_id, Comment),
            case z_acl:rsc_visible(RscId, Context) of
                true -> {ok, {Comment, Rest}};
                false -> {error, eacces}
            end
    end;
m_get(_Vs, _Msg, _Context) ->
    {error, unknown_path}.


%% @doc List all comments of the resource.
-spec list_rsc(m_rsc:resource(), z:context()) -> list().
list_rsc(RscId, Context) ->
    F = fun() ->
        z_db:assoc_props("select * from comment where rsc_id = $1 order by created asc", [m_rsc:rid(RscId, Context)], Context)
    end,
    z_depcache:memo(F, {comment_rsc, RscId}, ?MAXAGE_COMMENT, Context).


%% @doc Count comments of the resource.
%% @spec count_rsc(int(), Context) -> [ PropList ]
-spec count_rsc(m_rsc:resource(), z:context()) -> list().
count_rsc(RscId, Context) ->
    F = fun() ->
        z_db:q1("select count(*) from comment where rsc_id = $1", [m_rsc:rid(RscId, Context)], Context)
    end,
    z_depcache:memo(F, {comment_rsc_count, RscId}, ?MAXAGE_COMMENT, [{comment_rsc, RscId}], Context).


%% @doc Fetch a specific comment from the database.
%% @spec get(int(), Context) -> PropList
get(CommentId, Context) ->
    z_db:assoc_props_row("select * from comment where id = $1", [CommentId], Context).


%% @doc Insert a new comment. Fetches the submitter information from the Context.
-spec insert(m_rsc:resource(), Name::string(), Email::string(), Message::string(), Is_visible::boolean(), z:context()) -> {ok, pos_integer()} | {error, any()}.
insert(RscId, Name, Email, Message, Is_visible, Context) ->
    case z_acl:rsc_visible(RscId, Context)
        and (z_auth:is_auth(Context)
            orelse z_convert:to_bool(m_config:get_value(mod_comment, anonymous, true, Context))) of
        true ->
            Email = z_string:trim(Email),
            Name1 = z_html:escape(z_string:trim(Name)),
            Message1 = z_sanitize:escape_link(z_string:trim(Message), Context),
            KeepInformed = z_convert:to_bool(z_context:get_q(<<"keep_informed">>, Context, false)),
            UserAgent = z_context:get_q(<<"user_agent">>, Context, <<>>),
            IPAddress = z_convert:to_binary( m_req:get(peer, Context) ),
            {DeviceId, Context1} = case z_auth:is_auth(Context) of
                true ->
                    {undefined, Context};
                false ->
                    case m_client_local_storage:device_id(Context) of
                        {{ok, CId}, Ctx} -> {CId, Ctx};
                        {{error, _}, Ctx} -> {undefined, Ctx}
                    end
            end,
            Props = [
                {rsc_id, m_rsc:rid(RscId, Context)},
                {is_visible, Is_visible},
                {user_id, z_acl:user(Context)},
                {persistent_id, DeviceId},
                {name, Name1},
                {message, Message1},
                {email, Email},
                {gravatar_code, gravatar_code(Email)},
                {keep_informed, KeepInformed},
                {ip_address, IPAddress},
                {user_agent, UserAgent}
            ],
            {ok, CommentId} = Result = z_db:insert(comment, Props, Context1),
            z_depcache:flush({comment_rsc, RscId}, Context1),
            z_notifier:notify(#comment_insert{comment_id = CommentId, id = RscId}, Context1),
            Result;
        false ->
            {error, eacces}
    end.

%% @doc Delete a comment.  Only possible if the user has edit permission on the page.
delete(CommentId, Context) ->
    case check_editable(CommentId, Context) of
        {ok, RscId} ->
            z_db:q("delete from comment where id = $1", [CommentId], Context),
            z_depcache:flush({comment_rsc, RscId}, Context),
            ok;
        {error, _} = Error ->
            Error
    end.

%% @doc Check if a comment can be deleted
is_deletable(CommentId, Context) ->
    case check_editable(CommentId, Context) of
        {ok, _} -> true;
        {error, _} -> false
    end.

%% @doc Toggle the visibility of a comment, return the new visibility
toggle(CommentId, Context) ->
    case check_editable(CommentId, Context) of
        {ok, RscId} ->
            z_db:q("update comment
                    set is_visible = not is_visible
                    where id = $1",
                   [CommentId],
                   Context),
            z_depcache:flush({comment_rsc, RscId}, Context),
            {ok, z_db:q1("select is_visible from comment where id = $1", [CommentId], Context)};
        {error, _} = Error ->
            Error
    end.

%% @doc Check if an user can edit the comment
check_editable(CommentId, Context) ->
    case z_db:q_row("select rsc_id, user_id from comment where id = $1", [CommentId], Context) of
        {RscId, UserId} ->
            case (UserId /= undefined andalso z_acl:user(Context) == UserId)
                orelse z_acl:rsc_editable(RscId, Context)
            of
                true -> {ok, RscId};
                false -> {error, eacces}
            end;
        _ ->
            {error, enoent}
    end.


%% @doc Return the gravatar code of an email address. See also http://gravatar.com/
%% @spec gravatar_code(Email) -> list()
gravatar_code(Email) ->
    z_string:to_lower(z_utils:hex_encode(erlang:md5(z_string:to_lower(Email)))).


%% @doc Move all comments from one resource to another
-spec merge(m_rsc:resource(), m_rsc:resource(), z:context()) -> ok.
merge(WinnerId, LoserId, Context) ->
    z_db:q("update comment
            set rsc_id = $1
            where rsc_id = $2",
           [m_rsc:rid(WinnerId, Context), m_rsc:rid(LoserId, Context)],
           Context),
    z_depcache:flush({comment_rsc, m_rsc:rid(LoserId, Context)}, Context),
    z_depcache:flush({comment_rsc, m_rsc:rid(WinnerId, Context)}, Context),
    ok.


%% @doc Return the search as used by z_search and the search model.
search({recent_comments, []}, _OfffsetLimit, _Context) ->
    #search_sql{
        select="c.*",
        from="comment c",
        order="c.created desc",
        assoc=true
    }.
