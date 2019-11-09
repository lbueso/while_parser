-module(parser_erlang).
-export([parse/1, parse_and_scan/1, format_error/1]).
-file("src/parser_erlang.yrl", 33).

token_value({_, Val}) -> Val;
token_value({_, _, Val}) -> Val.
token_line({_, Line}) -> Line;
token_line({_, Line, _}) -> Line.



exp_line({exp, _, Line, _}) -> Line.

-file("/usr/lib64/erlang/lib/parsetools-2.1.8/include/yeccpre.hrl", 0).
%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1996-2018. All Rights Reserved.
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
%%
%% %CopyrightEnd%
%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% The parser generator will insert appropriate declarations before this line.%

-type yecc_ret() :: {'error', _} | {'ok', _}.

-spec parse(Tokens :: list()) -> yecc_ret().
parse(Tokens) ->
    yeccpars0(Tokens, {no_func, no_line}, 0, [], []).

-spec parse_and_scan({function() | {atom(), atom()}, [_]}
                     | {atom(), atom(), [_]}) -> yecc_ret().
parse_and_scan({F, A}) ->
    yeccpars0([], {{F, A}, no_line}, 0, [], []);
parse_and_scan({M, F, A}) ->
    Arity = length(A),
    yeccpars0([], {{fun M:F/Arity, A}, no_line}, 0, [], []).

-spec format_error(any()) -> [char() | list()].
format_error(Message) ->
    case io_lib:deep_char_list(Message) of
        true ->
            Message;
        _ ->
            io_lib:write(Message)
    end.

%% To be used in grammar files to throw an error message to the parser
%% toplevel. Doesn't have to be exported!
-compile({nowarn_unused_function, return_error/2}).
-spec return_error(integer(), any()) -> no_return().
return_error(Line, Message) ->
    throw({error, {Line, ?MODULE, Message}}).

-define(CODE_VERSION, "1.4").

yeccpars0(Tokens, Tzr, State, States, Vstack) ->
    try yeccpars1(Tokens, Tzr, State, States, Vstack)
    catch 
        error: Error: Stacktrace ->
            try yecc_error_type(Error, Stacktrace) of
                Desc ->
                    erlang:raise(error, {yecc_bug, ?CODE_VERSION, Desc},
                                 Stacktrace)
            catch _:_ -> erlang:raise(error, Error, Stacktrace)
            end;
        %% Probably thrown from return_error/2:
        throw: {error, {_Line, ?MODULE, _M}} = Error ->
            Error
    end.

yecc_error_type(function_clause, [{?MODULE,F,ArityOrArgs,_} | _]) ->
    case atom_to_list(F) of
        "yeccgoto_" ++ SymbolL ->
            {ok,[{atom,_,Symbol}],_} = erl_scan:string(SymbolL),
            State = case ArityOrArgs of
                        [S,_,_,_,_,_,_] -> S;
                        _ -> state_is_unknown
                    end,
            {Symbol, State, missing_in_goto_table}
    end.

yeccpars1([Token | Tokens], Tzr, State, States, Vstack) ->
    yeccpars2(State, element(1, Token), States, Vstack, Token, Tokens, Tzr);
yeccpars1([], {{F, A},_Line}, State, States, Vstack) ->
    case apply(F, A) of
        {ok, Tokens, Endline} ->
            yeccpars1(Tokens, {{F, A}, Endline}, State, States, Vstack);
        {eof, Endline} ->
            yeccpars1([], {no_func, Endline}, State, States, Vstack);
        {error, Descriptor, _Endline} ->
            {error, Descriptor}
    end;
yeccpars1([], {no_func, no_line}, State, States, Vstack) ->
    Line = 999999,
    yeccpars2(State, '$end', States, Vstack, yecc_end(Line), [],
              {no_func, Line});
yeccpars1([], {no_func, Endline}, State, States, Vstack) ->
    yeccpars2(State, '$end', States, Vstack, yecc_end(Endline), [],
              {no_func, Endline}).

%% yeccpars1/7 is called from generated code.
%%
%% When using the {includefile, Includefile} option, make sure that
%% yeccpars1/7 can be found by parsing the file without following
%% include directives. yecc will otherwise assume that an old
%% yeccpre.hrl is included (one which defines yeccpars1/5).
yeccpars1(State1, State, States, Vstack, Token0, [Token | Tokens], Tzr) ->
    yeccpars2(State, element(1, Token), [State1 | States],
              [Token0 | Vstack], Token, Tokens, Tzr);
yeccpars1(State1, State, States, Vstack, Token0, [], {{_F,_A}, _Line}=Tzr) ->
    yeccpars1([], Tzr, State, [State1 | States], [Token0 | Vstack]);
yeccpars1(State1, State, States, Vstack, Token0, [], {no_func, no_line}) ->
    Line = yecctoken_end_location(Token0),
    yeccpars2(State, '$end', [State1 | States], [Token0 | Vstack],
              yecc_end(Line), [], {no_func, Line});
yeccpars1(State1, State, States, Vstack, Token0, [], {no_func, Line}) ->
    yeccpars2(State, '$end', [State1 | States], [Token0 | Vstack],
              yecc_end(Line), [], {no_func, Line}).

%% For internal use only.
yecc_end({Line,_Column}) ->
    {'$end', Line};
yecc_end(Line) ->
    {'$end', Line}.

yecctoken_end_location(Token) ->
    try erl_anno:end_location(element(2, Token)) of
        undefined -> yecctoken_location(Token);
        Loc -> Loc
    catch _:_ -> yecctoken_location(Token)
    end.

-compile({nowarn_unused_function, yeccerror/1}).
yeccerror(Token) ->
    Text = yecctoken_to_string(Token),
    Location = yecctoken_location(Token),
    {error, {Location, ?MODULE, ["syntax error before: ", Text]}}.

-compile({nowarn_unused_function, yecctoken_to_string/1}).
yecctoken_to_string(Token) ->
    try erl_scan:text(Token) of
        undefined -> yecctoken2string(Token);
        Txt -> Txt
    catch _:_ -> yecctoken2string(Token)
    end.

yecctoken_location(Token) ->
    try erl_scan:location(Token)
    catch _:_ -> element(2, Token)
    end.

-compile({nowarn_unused_function, yecctoken2string/1}).
yecctoken2string({atom, _, A}) -> io_lib:write_atom(A);
yecctoken2string({integer,_,N}) -> io_lib:write(N);
yecctoken2string({float,_,F}) -> io_lib:write(F);
yecctoken2string({char,_,C}) -> io_lib:write_char(C);
yecctoken2string({var,_,V}) -> io_lib:format("~s", [V]);
yecctoken2string({string,_,S}) -> io_lib:write_string(S);
yecctoken2string({reserved_symbol, _, A}) -> io_lib:write(A);
yecctoken2string({_Cat, _, Val}) -> io_lib:format("~tp", [Val]);
yecctoken2string({dot, _}) -> "'.'";
yecctoken2string({'$end', _}) -> [];
yecctoken2string({Other, _}) when is_atom(Other) ->
    io_lib:write_atom(Other);
yecctoken2string(Other) ->
    io_lib:format("~tp", [Other]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



-file("src/parser_erlang.erl", 186).

-dialyzer({nowarn_function, yeccpars2/7}).
yeccpars2(0=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(1=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_1(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(2=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(3=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_3(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(4=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_4(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(5=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_5(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(6=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_6(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(7=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_7(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(8=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_8(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(9=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_9(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(10=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(11=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_11(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(12=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(13=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(14=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(15=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(16=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(17=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(18=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(19=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_19(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(20=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_20(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(21=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(22=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_22(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(23=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_23(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(24=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_24(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(25=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_25(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(26=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_26(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(27=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_27(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(28=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_28(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(Other, _, _, _, _, _, _) ->
 erlang:error({yecc_bug,"1.4",{missing_state_in_action_table, Other}}).

-dialyzer({nowarn_function, yeccpars2_0/7}).
yeccpars2_0(S, '(', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 2, Ss, Stack, T, Ts, Tzr);
yeccpars2_0(S, '-', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 3, Ss, Stack, T, Ts, Tzr);
yeccpars2_0(S, false, Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 4, Ss, Stack, T, Ts, Tzr);
yeccpars2_0(S, identifier, Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 5, Ss, Stack, T, Ts, Tzr);
yeccpars2_0(S, integer, Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 6, Ss, Stack, T, Ts, Tzr);
yeccpars2_0(S, true, Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 7, Ss, Stack, T, Ts, Tzr);
yeccpars2_0(_, _, _, _, T, _, _) ->
 yeccerror(T).

-dialyzer({nowarn_function, yeccpars2_1/7}).
yeccpars2_1(_S, '$end', _Ss, Stack, _T, _Ts, _Tzr) ->
 {ok, hd(Stack)};
yeccpars2_1(S, '&&', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 10, Ss, Stack, T, Ts, Tzr);
yeccpars2_1(S, '*', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 12, Ss, Stack, T, Ts, Tzr);
yeccpars2_1(S, '+', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 13, Ss, Stack, T, Ts, Tzr);
yeccpars2_1(S, '-', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 14, Ss, Stack, T, Ts, Tzr);
yeccpars2_1(S, '<=', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 15, Ss, Stack, T, Ts, Tzr);
yeccpars2_1(S, '==', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 16, Ss, Stack, T, Ts, Tzr);
yeccpars2_1(S, '?', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 17, Ss, Stack, T, Ts, Tzr);
yeccpars2_1(S, '||', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 18, Ss, Stack, T, Ts, Tzr);
yeccpars2_1(_, _, _, _, T, _, _) ->
 yeccerror(T).

%% yeccpars2_2: see yeccpars2_0

-dialyzer({nowarn_function, yeccpars2_3/7}).
yeccpars2_3(S, integer, Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 8, Ss, Stack, T, Ts, Tzr);
yeccpars2_3(_, _, _, _, T, _, _) ->
 yeccerror(T).

yeccpars2_4(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_4_(Stack),
 yeccgoto_exp(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

yeccpars2_5(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_5_(Stack),
 yeccgoto_exp(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

yeccpars2_6(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_6_(Stack),
 yeccgoto_exp(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

yeccpars2_7(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_7_(Stack),
 yeccgoto_exp(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

yeccpars2_8(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_|Nss] = Ss,
 NewStack = yeccpars2_8_(Stack),
 yeccgoto_exp(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

yeccpars2_9(S, ')', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 11, Ss, Stack, T, Ts, Tzr);
yeccpars2_9(S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_cont_9(S, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_9/7}).
yeccpars2_cont_9(S, '&&', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 10, Ss, Stack, T, Ts, Tzr);
yeccpars2_cont_9(S, '*', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 12, Ss, Stack, T, Ts, Tzr);
yeccpars2_cont_9(S, '+', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 13, Ss, Stack, T, Ts, Tzr);
yeccpars2_cont_9(S, '-', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 14, Ss, Stack, T, Ts, Tzr);
yeccpars2_cont_9(S, '<=', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 15, Ss, Stack, T, Ts, Tzr);
yeccpars2_cont_9(S, '==', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 16, Ss, Stack, T, Ts, Tzr);
yeccpars2_cont_9(S, '?', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 17, Ss, Stack, T, Ts, Tzr);
yeccpars2_cont_9(S, '||', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 18, Ss, Stack, T, Ts, Tzr);
yeccpars2_cont_9(_, _, _, _, T, _, _) ->
 yeccerror(T).

%% yeccpars2_10: see yeccpars2_0

yeccpars2_11(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_11_(Stack),
 yeccgoto_exp(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

%% yeccpars2_12: see yeccpars2_0

%% yeccpars2_13: see yeccpars2_0

%% yeccpars2_14: see yeccpars2_0

%% yeccpars2_15: see yeccpars2_0

%% yeccpars2_16: see yeccpars2_0

%% yeccpars2_17: see yeccpars2_0

%% yeccpars2_18: see yeccpars2_0

yeccpars2_19(S, '&&', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 10, Ss, Stack, T, Ts, Tzr);
yeccpars2_19(S, '*', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 12, Ss, Stack, T, Ts, Tzr);
yeccpars2_19(S, '+', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 13, Ss, Stack, T, Ts, Tzr);
yeccpars2_19(S, '-', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 14, Ss, Stack, T, Ts, Tzr);
yeccpars2_19(S, '<=', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 15, Ss, Stack, T, Ts, Tzr);
yeccpars2_19(S, '==', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 16, Ss, Stack, T, Ts, Tzr);
yeccpars2_19(S, '||', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 18, Ss, Stack, T, Ts, Tzr);
yeccpars2_19(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_19_(Stack),
 yeccgoto_exp(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

yeccpars2_20(S, ':', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 21, Ss, Stack, T, Ts, Tzr);
yeccpars2_20(S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_cont_9(S, Cat, Ss, Stack, T, Ts, Tzr).

%% yeccpars2_21: see yeccpars2_0

yeccpars2_22(S, '&&', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 10, Ss, Stack, T, Ts, Tzr);
yeccpars2_22(S, '*', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 12, Ss, Stack, T, Ts, Tzr);
yeccpars2_22(S, '+', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 13, Ss, Stack, T, Ts, Tzr);
yeccpars2_22(S, '-', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 14, Ss, Stack, T, Ts, Tzr);
yeccpars2_22(S, '<=', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 15, Ss, Stack, T, Ts, Tzr);
yeccpars2_22(S, '==', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 16, Ss, Stack, T, Ts, Tzr);
yeccpars2_22(S, '||', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 18, Ss, Stack, T, Ts, Tzr);
yeccpars2_22(_S, '$end', Ss, Stack, T, Ts, Tzr) ->
 [_,_,_,_|Nss] = Ss,
 NewStack = 'yeccpars2_22_\'$end\''(Stack),
 yeccgoto_exp(hd(Nss), '$end', Nss, NewStack, T, Ts, Tzr);
yeccpars2_22(_S, ')', Ss, Stack, T, Ts, Tzr) ->
 [_,_,_,_|Nss] = Ss,
 NewStack = 'yeccpars2_22_\')\''(Stack),
 yeccgoto_exp(hd(Nss), ')', Nss, NewStack, T, Ts, Tzr);
yeccpars2_22(_S, ':', Ss, Stack, T, Ts, Tzr) ->
 [_,_,_,_|Nss] = Ss,
 NewStack = 'yeccpars2_22_\':\''(Stack),
 yeccgoto_exp(hd(Nss), ':', Nss, NewStack, T, Ts, Tzr);
yeccpars2_22(_, _, _, _, T, _, _) ->
 yeccerror(T).

yeccpars2_23(S, '*', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 12, Ss, Stack, T, Ts, Tzr);
yeccpars2_23(S, '+', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 13, Ss, Stack, T, Ts, Tzr);
yeccpars2_23(S, '-', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 14, Ss, Stack, T, Ts, Tzr);
yeccpars2_23(_S, '$end', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_23_\'$end\''(Stack),
 yeccgoto_exp(hd(Nss), '$end', Nss, NewStack, T, Ts, Tzr);
yeccpars2_23(_S, '&&', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_23_\'&&\''(Stack),
 yeccgoto_exp(hd(Nss), '&&', Nss, NewStack, T, Ts, Tzr);
yeccpars2_23(_S, ')', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_23_\')\''(Stack),
 yeccgoto_exp(hd(Nss), ')', Nss, NewStack, T, Ts, Tzr);
yeccpars2_23(_S, ':', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_23_\':\''(Stack),
 yeccgoto_exp(hd(Nss), ':', Nss, NewStack, T, Ts, Tzr);
yeccpars2_23(_S, '?', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_23_\'?\''(Stack),
 yeccgoto_exp(hd(Nss), '?', Nss, NewStack, T, Ts, Tzr);
yeccpars2_23(_S, '||', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_23_\'||\''(Stack),
 yeccgoto_exp(hd(Nss), '||', Nss, NewStack, T, Ts, Tzr);
yeccpars2_23(_, _, _, _, T, _, _) ->
 yeccerror(T).

yeccpars2_24(S, '*', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 12, Ss, Stack, T, Ts, Tzr);
yeccpars2_24(S, '+', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 13, Ss, Stack, T, Ts, Tzr);
yeccpars2_24(S, '-', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 14, Ss, Stack, T, Ts, Tzr);
yeccpars2_24(_S, '$end', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_24_\'$end\''(Stack),
 yeccgoto_exp(hd(Nss), '$end', Nss, NewStack, T, Ts, Tzr);
yeccpars2_24(_S, '&&', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_24_\'&&\''(Stack),
 yeccgoto_exp(hd(Nss), '&&', Nss, NewStack, T, Ts, Tzr);
yeccpars2_24(_S, ')', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_24_\')\''(Stack),
 yeccgoto_exp(hd(Nss), ')', Nss, NewStack, T, Ts, Tzr);
yeccpars2_24(_S, ':', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_24_\':\''(Stack),
 yeccgoto_exp(hd(Nss), ':', Nss, NewStack, T, Ts, Tzr);
yeccpars2_24(_S, '?', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_24_\'?\''(Stack),
 yeccgoto_exp(hd(Nss), '?', Nss, NewStack, T, Ts, Tzr);
yeccpars2_24(_S, '||', Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = 'yeccpars2_24_\'||\''(Stack),
 yeccgoto_exp(hd(Nss), '||', Nss, NewStack, T, Ts, Tzr);
yeccpars2_24(_, _, _, _, T, _, _) ->
 yeccerror(T).

yeccpars2_25(S, '*', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 12, Ss, Stack, T, Ts, Tzr);
yeccpars2_25(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_25_(Stack),
 yeccgoto_exp(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

yeccpars2_26(S, '*', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 12, Ss, Stack, T, Ts, Tzr);
yeccpars2_26(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_26_(Stack),
 yeccgoto_exp(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

yeccpars2_27(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_27_(Stack),
 yeccgoto_exp(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

yeccpars2_28(S, '&&', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 10, Ss, Stack, T, Ts, Tzr);
yeccpars2_28(S, '*', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 12, Ss, Stack, T, Ts, Tzr);
yeccpars2_28(S, '+', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 13, Ss, Stack, T, Ts, Tzr);
yeccpars2_28(S, '-', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 14, Ss, Stack, T, Ts, Tzr);
yeccpars2_28(S, '<=', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 15, Ss, Stack, T, Ts, Tzr);
yeccpars2_28(S, '==', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 16, Ss, Stack, T, Ts, Tzr);
yeccpars2_28(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_28_(Stack),
 yeccgoto_exp(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_exp/7}).
yeccgoto_exp(0, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_1(1, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_exp(2, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_9(9, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_exp(10, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_28(28, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_exp(12=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_27(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_exp(13, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_26(26, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_exp(14, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_25(25, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_exp(15, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_24(24, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_exp(16, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_23(23, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_exp(17, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_20(20, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_exp(18, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_19(19, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_exp(21, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_22(22, Cat, Ss, Stack, T, Ts, Tzr).

-compile({inline,yeccpars2_4_/1}).
-file("src/parser_erlang.yrl", 14).
yeccpars2_4_(__Stack0) ->
 [__1 | __Stack] = __Stack0,
 [begin
   { exp , literal , token_line ( __1 ) , [ { boolean , true } ] }
  end | __Stack].

-compile({inline,yeccpars2_5_/1}).
-file("src/parser_erlang.yrl", 15).
yeccpars2_5_(__Stack0) ->
 [__1 | __Stack] = __Stack0,
 [begin
   { exp , variable , token_line ( __1 ) , [ { name , token_value ( __1 ) } ] }
  end | __Stack].

-compile({inline,yeccpars2_6_/1}).
-file("src/parser_erlang.yrl", 12).
yeccpars2_6_(__Stack0) ->
 [__1 | __Stack] = __Stack0,
 [begin
   { exp , literal , token_line ( __1 ) , [ { number , token_value ( __1 ) } ] }
  end | __Stack].

-compile({inline,yeccpars2_7_/1}).
-file("src/parser_erlang.yrl", 13).
yeccpars2_7_(__Stack0) ->
 [__1 | __Stack] = __Stack0,
 [begin
   { exp , literal , token_line ( __1 ) , [ { boolean , true } ] }
  end | __Stack].

-compile({inline,yeccpars2_8_/1}).
-file("src/parser_erlang.yrl", 16).
yeccpars2_8_(__Stack0) ->
 [__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , literal , token_line ( __1 ) , [ { number , - token_value ( __2 ) } ] }
  end | __Stack].

-compile({inline,yeccpars2_11_/1}).
-file("src/parser_erlang.yrl", 26).
yeccpars2_11_(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   __2
  end | __Stack].

-compile({inline,yeccpars2_19_/1}).
-file("src/parser_erlang.yrl", 23).
yeccpars2_19_(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , 'or' , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_22_\'$end\''/1}).
-file("src/parser_erlang.yrl", 25).
'yeccpars2_22_\'$end\''(__Stack0) ->
 [__5,__4,__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , conditional , exp_line ( __1 ) , [ { condition , __1 } , { 'if' , __3 } , { else , __5 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_22_\')\''/1}).
-file("src/parser_erlang.yrl", 25).
'yeccpars2_22_\')\''(__Stack0) ->
 [__5,__4,__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , conditional , exp_line ( __1 ) , [ { condition , __1 } , { 'if' , __3 } , { else , __5 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_22_\':\''/1}).
-file("src/parser_erlang.yrl", 25).
'yeccpars2_22_\':\''(__Stack0) ->
 [__5,__4,__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , conditional , exp_line ( __1 ) , [ { condition , __1 } , { 'if' , __3 } , { else , __5 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_23_\'$end\''/1}).
-file("src/parser_erlang.yrl", 21).
'yeccpars2_23_\'$end\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , eq , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_23_\'&&\''/1}).
-file("src/parser_erlang.yrl", 21).
'yeccpars2_23_\'&&\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , eq , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_23_\')\''/1}).
-file("src/parser_erlang.yrl", 21).
'yeccpars2_23_\')\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , eq , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_23_\':\''/1}).
-file("src/parser_erlang.yrl", 21).
'yeccpars2_23_\':\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , eq , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_23_\'?\''/1}).
-file("src/parser_erlang.yrl", 21).
'yeccpars2_23_\'?\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , eq , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_23_\'||\''/1}).
-file("src/parser_erlang.yrl", 21).
'yeccpars2_23_\'||\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , eq , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_24_\'$end\''/1}).
-file("src/parser_erlang.yrl", 20).
'yeccpars2_24_\'$end\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , lt , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_24_\'&&\''/1}).
-file("src/parser_erlang.yrl", 20).
'yeccpars2_24_\'&&\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , lt , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_24_\')\''/1}).
-file("src/parser_erlang.yrl", 20).
'yeccpars2_24_\')\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , lt , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_24_\':\''/1}).
-file("src/parser_erlang.yrl", 20).
'yeccpars2_24_\':\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , lt , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_24_\'?\''/1}).
-file("src/parser_erlang.yrl", 20).
'yeccpars2_24_\'?\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , lt , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,'yeccpars2_24_\'||\''/1}).
-file("src/parser_erlang.yrl", 20).
'yeccpars2_24_\'||\''(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , lt , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,yeccpars2_25_/1}).
-file("src/parser_erlang.yrl", 18).
yeccpars2_25_(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , sub , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,yeccpars2_26_/1}).
-file("src/parser_erlang.yrl", 17).
yeccpars2_26_(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , add , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,yeccpars2_27_/1}).
-file("src/parser_erlang.yrl", 19).
yeccpars2_27_(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , mul , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].

-compile({inline,yeccpars2_28_/1}).
-file("src/parser_erlang.yrl", 22).
yeccpars2_28_(__Stack0) ->
 [__3,__2,__1 | __Stack] = __Stack0,
 [begin
   { exp , 'and' , exp_line ( __1 ) , [ { lhs , __1 } , { rhs , __3 } ] }
  end | __Stack].


-file("src/parser_erlang.yrl", 43).
