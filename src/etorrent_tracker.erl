-module(etorrent_tracker).

-behaviour(gen_server).
%% API
-export([start_link/0,
         register_torrent/3,
         statechange/2,
         all/0,
         lookup/1]).

-export([init/1, handle_call/3, handle_cast/2, code_change/3,
         handle_info/2, terminate/2]).

-record(tracker, { 
        id :: non_neg_integer() | undefined,
        sup_pid :: pid(),
        torrent_id :: non_neg_integer(),
        tracker_url :: string(),
        tier_num :: non_neg_integer(),
        %% Time of previous announce try (it can fail or not).
        last_announced :: erlang:timestamp() | undefined,
        timeout :: non_neg_integer() | undefined}).

-define(SERVER, ?MODULE).
-define(TAB, ?MODULE).
-record(state, { 
        next_id = 1 :: non_neg_integer()
        }).

%% ====================================================================

%% @doc Start the `gen_server' governor.
%% @end
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Called from tracker communication server per torrent.
register_torrent(TorrentId, UrlTiers, SupPid) ->
    gen_server:cast(?SERVER, {register_torrent, TorrentId, UrlTiers, SupPid}).


%% @doc Return all torrents, sorted by Id
%% @end
-spec all() -> [[{term(), term()}]].
all() ->
    all(#tracker.id).

%% @doc Request a change of state for the tracker
%% <p>The specific What part is documented as the alteration() type
%% in the module.
%% </p>
%% @end
-type alteration() :: term().
-spec statechange(integer(), [alteration()]) -> ok.
statechange(Id, What) ->
    gen_server:cast(?SERVER, {statechange, Id, What}).

%% @doc Return a property list of the tracker identified by Id
%% @end
-spec lookup(integer()) ->
		    not_found | {value, [{term(), term()}]}.
lookup(Id) ->
    case ets:lookup(?TAB, Id) of
	[] -> not_found;
	[M] -> {value, proplistify(M)}
    end.


%% =======================================================================

%% @private
init([]) ->
    _ = ets:new(?TAB, [protected, named_table, {keypos, #tracker.id}]),
    {ok, #state{ }}.

%% @private
handle_call(_,_,_) ->
    {stop, badmsg}.

handle_cast({register_torrent, TorrentId, UrlTiers, SupPid}, S=#state{next_id=NextId}) ->
    {NextId2, Trackers} = create_tracker_records(TorrentId, UrlTiers, NextId, SupPid),
    ets:insert_new(?TAB, Trackers),
    monitor(process, SupPid),
    {noreply, S#state{next_id=NextId2}};

%% @private
handle_cast({statechange, Id, What}, S) ->
    state_change(Id, What),
    {noreply, S}.

%% @private
handle_info({'DOWN', _Ref, process, Pid, _}, S) ->
    ets:match_delete(?TAB, #tracker{_='_', sup_pid=Pid}),
    {noreply, S}.

%% @private
code_change(_OldVsn, S, _Extra) ->
    {ok, S}.

%% @private
terminate(_Reason, _S) ->
    ok.

%% -----------------------------------------------------------------------


%%--------------------------------------------------------------------
%% Function: all(Pos) -> Rows
%% Description: Return all torrents, sorted by Pos
%%--------------------------------------------------------------------
all(Pos) ->
    Objects = ets:match_object(?TAB, '$1'),
    lists:keysort(Pos, Objects),
    [proplistify(O) || O <- Objects].

proplistify(T) ->
    [{id,               T#tracker.id}
    ,{torrent_id,       T#tracker.torrent_id}].

%% Change the state of the tracker with Id, altering it by the "What" part.
%% Precondition: Torrent exists in the ETS table.
state_change(Id, List) when is_integer(Id) ->
    case ets:lookup(?TAB, Id) of
        [T] ->
            NewT = do_state_change(List, T),
            ets:insert(?TAB, NewT);
        []   ->
            %% This is protection against bad tracker ids.
            lager:error("Not found ~p, skip.", [Id]),
            {error, not_found}
    end.

do_state_change([announced | Rem], T) ->
    do_state_change(Rem, T#tracker{last_announced = os:timestamp()});
do_state_change([], T) ->
    T.


create_tracker_records(TorrentId, UrlTiers, NextId, SupPid) ->
    per_pier(TorrentId, UrlTiers, 1, NextId, SupPid, []).

per_pier(TorrentId, [UrlTier|UrlTiers], TierNum, NextId, SupPid, Acc) ->
    {NextId2, Acc2} = per_url(TorrentId, UrlTier, TierNum, NextId, SupPid, Acc),
    per_pier(TorrentId, UrlTiers, TierNum+1, NextId2, SupPid, Acc2);
per_pier(_TorrentId, [], _TierNum, NextId, _SupPid, Acc) ->
    {NextId, Acc}.

per_url(TorrentId, [Url|Urls], TierNum, NextId, SupPid, Acc) ->
    T = #tracker{id=NextId, torrent_id=TorrentId, tracker_url=Url, tier_num=TierNum},
    per_url(TorrentId, Urls, TierNum, NextId+1, SupPid, [T|Acc]);
per_url(_TorrentId, [], _TierNum, NextId, _SupPid, Acc) ->
    {NextId, Acc}.
