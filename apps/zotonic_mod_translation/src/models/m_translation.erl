%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2013-2023 Marc Worrell
%% @doc Model for access to request language, language lists and language configuration.
%% @end

%% Copyright 2013-2023 Marc Worrell
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

-module(m_translation).
-author("Marc Worrell <marc@worrell.nl").

-behaviour(zotonic_model).

%% interface functions
-export([
    m_get/3,

    language_list_configured/1,
    language_list_enabled/1,
    language_list_editable/1,
    main_languages/0,
    all_languages/0,

    query_language/1,

    add_properties/1,
    sort_codes/1,
    sort/1
]).


%% @doc Fetch the value for the key from a model source
-spec m_get( list(), zotonic_model:opt_msg(), z:context() ) -> zotonic_model:return().
m_get([ <<"rewrite_url">> | Rest ], _Msg, Context) ->
    {ok, {m_config:get_boolean(mod_translation, rewrite_url, true, Context), Rest}};
m_get([ <<"force_default">> | Rest ], _Msg, Context) ->
    {ok, {m_config:get_boolean(mod_translation, force_default, false, Context), Rest}};
m_get([ <<"language">> | Rest ], _Msg, Context) ->
    {ok, {z_context:language(Context), Rest}};
m_get([ <<"language_list_configured">> | Rest ], _Msg, Context) ->
    {ok, {language_list_configured(Context), Rest}};
m_get([ <<"language_list_enabled">> | Rest ], _Msg, Context) ->
    {ok, {language_list_enabled(Context), Rest}};
m_get([ <<"language_list_editable">> | Rest ], _Msg, Context) ->
    {ok, {language_list_editable(Context), Rest}};
m_get([ <<"default_language">> | Rest ], _Msg, Context) ->
    {ok, {z_language:default_language(Context), Rest}};
m_get([ <<"query_language">> | Rest ], _Msg, Context) ->
    {ok, {query_language(Context), Rest}};
m_get([ <<"x_default_language">> | Rest ], _Msg, Context) ->
    Lang = case m_config:get_boolean(mod_translation, force_default, false, Context) of
        true ->
            z_language:default_language(Context);
        false ->
            'x-default'
    end,
    {ok, {Lang, Rest}};
m_get([ <<"main_languages">> | Rest ], _Msg, _Context) ->
    {ok, {main_languages(), Rest}};
m_get([ <<"all_languages">> | Rest ], _Msg, _Context) ->
    {ok, {all_languages(), Rest}};
m_get([ <<"enabled_language_codes">> | Rest ], _Msg, Context) ->
    {ok, {z_language:enabled_language_codes(Context), Rest}};
m_get([ <<"language_list">> | Rest ], _Msg, Context) ->
    {ok, {z_language:language_list(Context), Rest}};
m_get([ <<"language_stemmer">> | Rest ], _Msg, Context) ->
    Stemmer = case m_config:get_value(i18n, language_stemmer, Context) of
        undefined -> z_language:default_language(Context);
        <<>> -> z_language:default_language(Context);
        St -> St
    end,
    {ok, {Stemmer, Rest}};
m_get([ <<"name">>, Code | Rest ], _Msg, _Context) ->
    {ok, {z_language:local_name(Code), Rest}};
m_get([ <<"english_name">>, Code | Rest ], _Msg, _Context) ->
    {ok, {z_language:english_name(Code), Rest}};
m_get([ <<"properties">>, Code | Rest ], _Msg, _Context) ->
    {ok, {z_language:properties(Code), Rest}};
m_get(_Vs, _Msg, _Context) ->
    {error, unknown_path}.

language_list_configured(Context) ->
    Default = z_language:default_language(Context),
    Config = z_language:language_config(Context),
    List = lists:map(
        fun
            ({Code, _}) when Code =:= Default ->
                Props = z_language:properties(Code),
                {Code, Props#{ is_enabled => true, is_editable => true, is_default => true } };
            ({Code, true}) ->
                Props = z_language:properties(Code),
                {Code, Props#{ is_enabled => true, is_editable => true, is_default => false } };
            ({Code, editable}) ->
                Props = z_language:properties(Code),
                {Code, Props#{ is_enabled => false, is_editable => true, is_default => false } };
            ({Code, false}) ->
                Props = z_language:properties(Code),
                {Code, Props#{ is_enabled => false, is_editable => false, is_default => false } }
        end,
        Config),
    % Ensure the default language is enabled
    List1 = case Default =:= undefined orelse proplists:is_defined(Default, Config) of
        true ->
            List;
        false ->
            Props = z_language:properties(Default),
            [ {Default, Props#{ is_enabled => true, is_editable => true, is_default => true } } | List ]
    end,
    List1.

language_list_enabled(Context) ->
	add_properties(z_language:enabled_languages(Context)).

language_list_editable(Context) ->
    add_properties(z_language:editable_languages(Context)).

main_languages() ->
    sort(z_language:main_languages()).

all_languages() ->
    sort(z_language:all_languages()).

%% @doc Return the specific language as requested in the current HTTP query (URL).
%% Return 'x-default' if there isn't a HTTP request or no language was
%% specified in the current request.
-spec query_language(Context) -> Language when
    Context :: z:context(),
    Language :: atom().
query_language(Context) ->
    case mod_translation:get_q_language(Context) of
        undefined ->
            'x-default';
        Language ->
            Language
    end.

add_properties(Codes) ->
    lists:map(
        fun(Code) ->
            {Code, z_language:properties(Code)}
        end,
        Codes).

sort_codes(Codes) when is_list(Codes) ->
    sort(add_properties(Codes)).

sort(Map) when is_map(Map) ->
    List = maps:fold(
        fun
            (K, V, Acc) when is_atom(K) ->
                [ {K, V} | Acc ];
            (_, _, Acc) ->
                Acc
        end,
        [],
        Map),
    sort(List);
sort(List) ->
    lists:sort(fun sortfun/2, List).

sortfun({_, As}, {_, Bs}) ->
    maps:get(sort_key, As) =< maps:get(sort_key, Bs).

