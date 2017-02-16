%%% ocs_rest_api_SUITE.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  @doc Test suite for REST API 
%%% 	of the {@link //ocs. ocs} application.
%%%
-module(ocs_rest_api_SUITE).
-copyright('Copyright (c) 2016 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

-compile(export_all).

-include_lib("radius/include/radius.hrl").
-include("ocs_eap_codec.hrl").
-include_lib("common_test/include/ct.hrl").

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	[{userdata, [{doc, "Test suite for REST API in OCS"}]}, 
	{timetrap, {minutes, 1}},
	{require, rest_user}, {default_config, rest_user, "bss"},
	{require, rest_pass}, {default_config, rest_pass, "nfc9xgp32xha"},
	{require, rest_group}, {default_config, rest_group, "all"}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before the whole suite.
%%
init_per_suite(Config) ->
	ok = ocs_test_lib:initialize_db(),
	ok = ocs_test_lib:start(),
	{ok, Services} = application:get_env(inets, services),
	Fport = fun(F, [{httpd, L} | T]) ->
				case lists:keyfind(server_name, 1, L) of
					{_, "rest"} ->
						H1 = lists:keyfind(bind_address, 1, L),
						P1 = lists:keyfind(port, 1, L),
						{H1, P1};
					_ ->
						F(F, T)
				end;
			(F, [_ | T]) ->
				F(F, T)
	end,
	RestUser = ct:get_config(rest_user), 
	RestPass = ct:get_config(rest_pass), 
	RestGroup = ct:get_config(rest_group),
	{Host, Port} = case Fport(Fport, Services) of
		{{_, H2}, {_, P2}} when H2 == "localhost"; H2 == {127,0,0,1} -> 
			true = mod_auth:add_user(RestUser, RestPass, [], {127,0,0,1}, P2, "/"),
			true = mod_auth:add_group_member(RestGroup, RestUser, {127,0,0,1}, P2, "/"),
			{"localhost", P2}; 
		{{_, H2}, {_, P2}} -> 
			true = mod_auth:add_user(RestUser, RestPass, [], H2, P2, "/"),
			true = mod_auth:add_group_member(RestGroup, RestUser, H2, P2, "/"),
			case H2 of
				H2 when is_tuple(H2) ->
					{inet:ntoa(H2), P2};
				H2 when is_list(H2) ->
					{H2, P2}
			end; 
		{false, {_, P2}} -> 
			true = mod_auth:add_user(RestUser, RestPass, [], P2, "/"),
			true = mod_auth:add_group_member(RestGroup, RestUser, P2, "/"),
			{"localhost", P2} 
	end,
	Config1 = [{port, Port} | Config],
	HostUrl = "https://" ++ Host ++ ":" ++ integer_to_list(Port),
	[{host_url, HostUrl} | Config1].

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(Config) ->
	ok = ocs_test_lib:stop(),
	Config.

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before each test case.
%%
init_per_testcase(_TestCase, Config) ->
	{ok, IP} = application:get_env(ocs, radius_auth_addr),
	{ok, Socket} = gen_udp:open(0, [{active, false}, inet, {ip, IP}, binary]),
	[{socket, Socket} | Config].

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(_TestCase, Config) ->
	Socket = ?config(socket, Config),
	ok =  gen_udp:close(Socket).

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() -> 
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() -> 
	[add_subscriber, get_subscriber].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

add_subscriber() ->
	[{userdata, [{doc,"Add subscriber in rest interface"}]}].

add_subscriber(Config) ->
	ContentType = "application/json",
	ID = "eacfd73ae10a",
	Password = "ksc8c244npqc",
	AsendDataRate = {struct, [{"name", "ascendDataRate"}, {"type", 26},
		{"vendorId", 529}, {"vendorType", 197}, {"value", 1024}]}, 
	AsendXmitRate = {struct, [{"name", "ascendXmitRate"}, {"type", 26}, 
		{"vendorId", 529}, {"vendorType", 255}, {"value", 512}]}, 
	SessionTimeout = {struct, [{"name", "sessionTimeout"}, {"value", 10864}]}, 
	Interval = {struct, [{"name", "acctInterimInterval"}, {"value", 300}]}, 
	Class = {struct, [{"name", "class"}, {"value", "skiorgs"}]},
	SortedAttributes = lists:sort([AsendDataRate, AsendXmitRate, SessionTimeout, Interval, Class]),
	AttributeArray = {array, SortedAttributes},
	Balance = 100,
	Enable = true,
	JSON1 = {struct, [{"id", ID}, {"password", Password},
	{"attributes", AttributeArray}, {"balance", Balance}, {"enabled", Enable}]},
	RequestBody = lists:flatten(mochijson:encode(JSON1)),
	HostUrl = ?config(host_url, Config),
	Accept = {"accept", "application/json"},
	RestUser = ct:get_config(rest_user),
	RestPass = ct:get_config(rest_pass),
	Encodekey = base64:encode_to_string(string:concat(RestUser ++ ":", RestPass)),
	AuthKey = "Basic " ++ Encodekey,
   Authentication = {"authorization", AuthKey},
	Request = {HostUrl ++ "/ocs/v1/subscriber", [Accept, Authentication], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{_, URI} = lists:keyfind("location", 1, Headers),
	{_, _, "/ocs/v1/subscriber/" ++ RuleID, _, _} = mochiweb_util:urlsplit(URI),
	{struct, Object} = mochijson:decode(ResponseBody),
	{"id", ID} = lists:keyfind("id", 1, Object),
	{_, URI} = lists:keyfind("href", 1, Object),
	{"password", Password} = lists:keyfind("password", 1, Object),
	{_, {array, Attributes}} = lists:keyfind("attributes", 1, Object),
	ExtraAttributes = Attributes -- SortedAttributes, 
	SortedAttributes = lists:sort(Attributes -- ExtraAttributes),
	{"balance", Balance} = lists:keyfind("balance", 1, Object),
	{"enabled", Enable} = lists:keyfind("enabled", 1, Object).

get_subscriber() ->
   [{userdata, [{doc,"get subscriber in rest interface"}]}].

get_subscriber(Config) ->
	ContentType = "application/json",
	ID = "eacfd73ae10a",
	Password = "ksc8c244npqc",
	AsendDataRate = {struct, [{"name", "ascendDataRate"}, {"type", 26},
		{"vendorId", 529}, {"vendorType", 197}, {"value", 1024}]}, 
	AsendXmitRate = {struct, [{"name", "ascendXmitRate"}, {"type", 26}, 
		{"vendorId", 529}, {"vendorType", 255}, {"value", 512}]}, 
	SessionTimeout = {struct, [{"name", "sessionTimeout"}, {"value", 10864}]}, 
	Interval = {struct, [{"name", "acctInterimInterval"}, {"value", 300}]}, 
	Class = {struct, [{"name", "class"}, {"value", "skiorgs"}]},
	SortedAttributes = lists:sort([AsendDataRate, AsendXmitRate, SessionTimeout, Interval, Class]),
	AttributeArray = {array, SortedAttributes},
	Balance = 100,
	Enable = true,
	JSON1 = {struct, [{"id", ID}, {"password", Password},
	{"attributes", AttributeArray}, {"balance", Balance}, {"enabled", Enable}]},
   RequestBody = lists:flatten(mochijson:encode(JSON1)),
   HostUrl = ?config(host_url, Config),
   Accept = {"accept", "application/json"},
	RestUser = ct:get_config(rest_user),
	RestPass = ct:get_config(rest_pass),
	Encodekey = base64:encode_to_string(string:concat(RestUser ++ ":", RestPass)),
	AuthKey = "Basic " ++ Encodekey,
   Authentication = {"authorization", AuthKey},
   Request1 = {HostUrl ++ "/ocs/v1/subscriber", [Accept, Authentication], ContentType, RequestBody},
   {ok, Result} = httpc:request(post, Request1, [], []),
   {{"HTTP/1.1", 201, _Created}, Headers, _} = Result,
   {_, URI1} = lists:keyfind("location", 1, Headers),
   {_, _, URI2, _, _} = mochiweb_util:urlsplit(URI1),
   Request2 = {HostUrl ++ URI2, [Accept, Authentication ]},
   {ok, Result1} = httpc:request(get, Request2, [], []),
   {{"HTTP/1.1", 200, _OK}, Headers1, Body1} = Result1,
   {_, Accept} = lists:keyfind("content-type", 1, Headers1),
   ContentLength = integer_to_list(length(Body1)),
   {_, ContentLength} = lists:keyfind("content-length", 1, Headers1),
   {struct, Object} = mochijson:decode(Body1),
	{"id", ID} = lists:keyfind("id", 1, Object),
	{_, URI} = lists:keyfind("href", 1, Object),
	{"password", Password} = lists:keyfind("password", 1, Object),
	{_, {array, Attributes}} = lists:keyfind("attributes", 1, Object),
	ExtraAttributes = Attributes -- SortedAttributes, 
	SortedAttributes = lists:sort(Attributes -- ExtraAttributes),
	{"balance", Balance} = lists:keyfind("balance", 1, Object),
	{"enabled", Enable} = lists:keyfind("enabled", 1, Object).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

