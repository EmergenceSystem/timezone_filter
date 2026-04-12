%%%-------------------------------------------------------------------
%%% @doc World time and timezone information agent.
%%%
%%% Returns the current local time, UTC offset, DST status, and DST
%%% interval for a given timezone via timeapi.io (free, no key).
%%%
%%% API: https://timeapi.io/api/timezone/zone?timeZone={zone}
%%%
%%% Query forms accepted:
%%%   "Europe/Paris", "America/New_York", "Asia/Tokyo"
%%%   "Paris", "Tokyo", "New York"  (city→zone mapping)
%%%   "UTC", "GMT"
%%%
%%% Handler contract: handle/2 (Body, Memory) -> {RawList, Memory}.
%%% @end
%%%-------------------------------------------------------------------
-module(timezone_filter_app).
-behaviour(application).

-export([start/2, stop/1]).
-export([handle/2, base_capabilities/0]).

-define(BASE_URL, "https://timeapi.io/api/timezone/zone?timeZone=").

%%====================================================================
%% Capability cascade
%%====================================================================

-spec base_capabilities() -> [binary()].
base_capabilities() ->
    em_filter:base_capabilities() ++ [<<"timezone">>, <<"time">>,
                                      <<"clock">>, <<"dst">>,
                                      <<"world">>].

%%====================================================================
%% Application behaviour
%%====================================================================

start(_Type, _Args) ->
    em_filter:start_agent(timezone_filter, ?MODULE, #{
        capabilities => base_capabilities()
    }),
    {ok, self()}.

stop(_State) ->
    em_filter:stop_agent(timezone_filter).

%%====================================================================
%% Agent handler
%%====================================================================

handle(Body, Memory) when is_binary(Body) ->
    {generate_embryo_list(Body), Memory};
handle(_Body, Memory) ->
    {[], Memory}.

%%====================================================================
%% Query processing
%%====================================================================

generate_embryo_list(JsonBinary) ->
    {Query, Timeout} = extract_params(JsonBinary),
    Zone = resolve_zone(string:trim(Query)),
    fetch_time(Zone, Timeout).

extract_params(JsonBinary) ->
    try json:decode(JsonBinary) of
        Map when is_map(Map) ->
            Query = binary_to_list(maps:get(<<"value">>, Map,
                        maps:get(<<"query">>, Map,
                        maps:get(<<"zone">>, Map, <<"">>)))),
            Timeout = to_timeout(maps:get(<<"timeout">>, Map, undefined)),
            {Query, Timeout};
        _ ->
            {binary_to_list(JsonBinary), 10}
    catch
        _:_ -> {binary_to_list(JsonBinary), 10}
    end.

%% Map common city names to IANA timezone identifiers.
%% If the query already contains "/" it is treated as an IANA zone.
-spec resolve_zone(string()) -> string().
resolve_zone("") -> "UTC";
resolve_zone(Q) ->
    case string:find(Q, "/") of
        nomatch ->
            QL = string:lowercase(Q),
            case city_alias(QL) of
                {ok, Zone} -> Zone;
                none       -> Q
            end;
        _ -> Q
    end.

city_alias("paris")          -> {ok, "Europe/Paris"};
city_alias("london")         -> {ok, "Europe/London"};
city_alias("berlin")         -> {ok, "Europe/Berlin"};
city_alias("madrid")         -> {ok, "Europe/Madrid"};
city_alias("rome")           -> {ok, "Europe/Rome"};
city_alias("amsterdam")      -> {ok, "Europe/Amsterdam"};
city_alias("brussels")       -> {ok, "Europe/Brussels"};
city_alias("zurich")         -> {ok, "Europe/Zurich"};
city_alias("stockholm")      -> {ok, "Europe/Stockholm"};
city_alias("oslo")           -> {ok, "Europe/Oslo"};
city_alias("helsinki")       -> {ok, "Europe/Helsinki"};
city_alias("moscow")         -> {ok, "Europe/Moscow"};
city_alias("istanbul")       -> {ok, "Europe/Istanbul"};
city_alias("dubai")          -> {ok, "Asia/Dubai"};
city_alias("tokyo")          -> {ok, "Asia/Tokyo"};
city_alias("beijing")        -> {ok, "Asia/Shanghai"};
city_alias("shanghai")       -> {ok, "Asia/Shanghai"};
city_alias("hong kong")      -> {ok, "Asia/Hong_Kong"};
city_alias("singapore")      -> {ok, "Asia/Singapore"};
city_alias("sydney")         -> {ok, "Australia/Sydney"};
city_alias("melbourne")      -> {ok, "Australia/Melbourne"};
city_alias("new york")       -> {ok, "America/New_York"};
city_alias("los angeles")    -> {ok, "America/Los_Angeles"};
city_alias("chicago")        -> {ok, "America/Chicago"};
city_alias("toronto")        -> {ok, "America/Toronto"};
city_alias("montreal")       -> {ok, "America/Montreal"};
city_alias("mexico city")    -> {ok, "America/Mexico_City"};
city_alias("sao paulo")      -> {ok, "America/Sao_Paulo"};
city_alias("buenos aires")   -> {ok, "America/Argentina/Buenos_Aires"};
city_alias("utc")            -> {ok, "UTC"};
city_alias("gmt")            -> {ok, "GMT"};
city_alias(_)                -> none.

%%====================================================================
%% Fetch and parse
%%====================================================================

fetch_time("", _) -> [];
fetch_time(Zone, Timeout) ->
    Url = lists:flatten(io_lib:format("~s~s",
              [?BASE_URL, uri_string:quote(Zone)])),
    case httpc:request(get, {Url, []},
                       [{timeout, Timeout * 1000},
                        {ssl, [{verify, verify_none}]}],
                       [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, Body}} -> parse_time(Body);
        _                            -> []
    end.

parse_time(JsonBin) ->
    try json:decode(JsonBin) of
        Info when is_map(Info) -> [build_embryo(Info)];
        _                      -> []
    catch
        _:_ -> []
    end.

build_embryo(Info) ->
    Zone    = maps:get(<<"timeZone">>,            Info, <<"">>),
    LT      = maps:get(<<"currentLocalTime">>,    Info, <<"">>),
    UtcOff  = nested(Info, [<<"currentUtcOffset">>, <<"seconds">>], 0),
    DST     = maps:get(<<"isDayLightSavingActive">>, Info, false),
    DstName = nested(Info, [<<"dstInterval">>, <<"dstName">>], <<"">>),
    DstEnd  = nested(Info, [<<"dstInterval">>, <<"dstEnd">>],  <<"">>),

    %% Extract date and time from ISO datetime "2026-04-12T10:04:55.524"
    {DateStr, TimeStr} = split_datetime(LT),

    OffStr  = format_offset(UtcOff),
    DstStr  = case DST of
        true  -> iolist_to_binary([" ", DstName, " (DST until ", DstEnd, ")"]);
        false -> <<" (no DST)">>
    end,

    Title  = iolist_to_binary([Zone, " — ", TimeStr, " ", DateStr]),
    Resume = iolist_to_binary(["UTC", OffStr, DstStr]),

    #{<<"properties">> => #{
        <<"url">>    => iolist_to_binary(["https://timeapi.io/api/timezone/zone?timeZone=", Zone]),
        <<"title">>  => Title,
        <<"resume">> => Resume,
        <<"source">> => <<"timeapi.io">>
    }}.

split_datetime(DT) when is_binary(DT) ->
    case binary:split(DT, <<"T">>) of
        [Date, TimeRaw] ->
            %% Trim sub-seconds from time
            Time = case binary:split(TimeRaw, <<".">>) of
                [T, _] -> T;
                [T]    -> T
            end,
            {Date, Time};
        _ -> {DT, <<"">>}
    end;
split_datetime(_) -> {<<"">>, <<"">>}.

format_offset(Secs) when is_integer(Secs) ->
    Sign = if Secs >= 0 -> "+"; true -> "-" end,
    Abs  = abs(Secs),
    H    = Abs div 3600,
    M    = (Abs rem 3600) div 60,
    lists:flatten(io_lib:format("~s~2..0B:~2..0B", [Sign, H, M]));
format_offset(_) -> "+00:00".

nested(Map, [Key], Default) ->
    maps:get(Key, Map, Default);
nested(Map, [Key | Rest], Default) ->
    case maps:get(Key, Map, undefined) of
        Sub when is_map(Sub) -> nested(Sub, Rest, Default);
        _                    -> Default
    end.

%%====================================================================
%% Helpers
%%====================================================================

to_timeout(undefined)            -> 10;
to_timeout(T) when is_integer(T) -> T;
to_timeout(T) when is_binary(T)  ->
    try binary_to_integer(T) catch _:_ -> 10 end;
to_timeout(_) -> 10.
