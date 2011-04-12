-module(ddfs).

-include("config.hrl").
-include("ddfs_tag.hrl").

-export([new_blob/4, tags/2, get_tag/4, update_tag/5, update_tag_delayed/5,
         replace_tag/5, delete/3, delete_attrib/4]).

-spec new_blob(node(), string(), non_neg_integer(), [node()]) ->
    'invalid_name' | 'too_many_replicas' | {'ok', [string()]} | _.
new_blob(Host, Blob, Replicas, Exclude) ->
    validate(Blob, fun() ->
        Obj = [Blob, "$", ddfs_util:timestamp()],
        gen_server:call(Host, {new_blob, Obj, Replicas, Exclude})
    end).

-spec tags(node(), binary()) -> {'ok', [binary()]}.
tags(Host, Prefix) ->
    case gen_server:call(Host, {get_tags, safe}, ?NODEOP_TIMEOUT) of
        {ok, Tags} ->
            {ok, if Prefix =:= <<>> ->
                Tags;
            true ->
                [T || T <- Tags, ddfs_util:startswith(T, Prefix)]
            end};
        E -> E
    end.

-spec get_tag(node(), nonempty_string(), atom() | string(), token() | 'internal') ->
    'invalid_name' | {'missing', _} | 'unknown_attribute'
    | {'ok', binary()} | {'error', _}.
get_tag(Host, Tag, Attrib, Token) ->
    tagop(Host, Tag, {get, Attrib, Token}, ?NODEOP_TIMEOUT).

-spec update_tag(node(), nonempty_string(), [[binary()]], token(), [term()]) -> _.
update_tag(Host, Tag, Urls, Token, Opt) ->
    tagop(Host, Tag, {update, Urls, Token, Opt}).

-spec update_tag_delayed(node(), nonempty_string(), [[binary()]],
                         token(), [term()]) -> _.
update_tag_delayed(Host, Tag, Urls, Token, Opt) ->
    tagop(Host, Tag, {delayed_update, Urls, Token, Opt}).

-spec replace_tag(node(), nonempty_string(),
                  attrib(), [binary()] | [[binary()]], token()) -> _.
replace_tag(Host, Tag, Field, Value, Token) ->
    tagop(Host, Tag, {put, Field, Value, Token}).

-spec delete_attrib(node(), nonempty_string(), attrib(), token()) -> _.
delete_attrib(Host, Tag, Field, Token) ->
    tagop(Host, Tag, {delete_attrib, Field, Token}).

-spec delete(node(), nonempty_string(), token() | 'internal') -> term().
delete(Host, Tag, Token) ->
    tagop(Host, Tag, {delete, Token}).

-spec tagop(node(), nonempty_string(),
            {'delete', _}
            | {'delete_attrib', _, _}
            | {'delayed_update', _, _, _}
            | {'update', _, _, _}
            | {'put', _, _, _}) -> term().
tagop(Host, Tag, Op) ->
    tagop(Host, Tag, Op, ?TAG_UPDATE_TIMEOUT).
tagop(Host, Tag, Op, Timeout) ->
    validate(Tag, fun() ->
                      gen_server:call(Host,
                                      {tag, Op, list_to_binary(Tag)}, Timeout)
                  end).

-spec validate(nonempty_string(), fun(()-> T)) -> T.
validate(Name, Fun) ->
    case ddfs_util:is_valid_name(Name) of
        false ->
            {error, invalid_name};
        true ->
            case catch Fun() of
                {'EXIT', {timeout, _}} ->
                    {error, timeout};
                Ret ->
                    Ret
            end
    end.
