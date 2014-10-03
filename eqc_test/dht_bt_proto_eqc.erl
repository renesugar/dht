-module(dht_bt_proto_eqc).

-compile(export_all).

-include_lib("eqc/include/eqc.hrl").

%% Generators

ping() ->
    return(ping).
    
find_node() ->
    ?LET(ID, dht_eqc:id(),
        {find_node, ID}).

get_peers() ->
    ?LET(ID, dht_eqc:id(),
        {get_peers, ID}).
        
announce() ->
    ?LET([ID, Token, Port], [dht_eqc:id(), dht_eqc:token(), dht_eqc:port()],
        {announce, ID, Token, Port}).

g_query() ->
    ?LET({Cmd, OwnID, MsgID}, {oneof([ping(), find_node(), get_peers(), announce()]), dht_eqc:id(), dht_eqc:msg_id()},
        {query, OwnID, MsgID, Cmd}).
        
r_ping() ->
    ?LET({ID, MsgID}, {dht_eqc:id(), dht_eqc:msg_id()},
        {ping, {response, ID, MsgID, ping}}).

r_find_node() ->
    ?LET({ID, MsgID, Ns}, {dht_eqc:id(), dht_eqc:msg_id(), list({dht_eqc:ip(), dht_eqc:port()})},
        {find_node, {response, ID, MsgID, {find_node, Ns}}}).

g_response() ->
    oneof([
        r_ping(),
        r_find_node()
    ]).

g_error() ->
    ?LET({MsgID, Code, Msg}, {dht_eqc:msg_id(), int(), binary()},
        {na, {error, MsgID, Code, Msg}}).

%% Properties
prop_iso_query() ->
    ?FORALL(Q, g_query(),
        begin
            E = iolist_to_binary(dht_bt_proto:encode(Q)),
            equals(Q, dht_bt_proto:decode_as_query(E))
        end).

prop_iso_responses() ->
    ?FORALL({M, R}, frequency([{1, g_error()}, {5, g_response()}]),
        begin
             E = iolist_to_binary(dht_bt_proto:encode(R)),
             equals(R, dht_bt_proto:decode_as_response(M, E))
        end).
