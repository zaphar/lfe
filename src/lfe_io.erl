%% Copyright (c) 2008 Robert Virding. All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions
%% are met:
%%
%% 1. Redistributions of source code must retain the above copyright
%%    notice, this list of conditions and the following disclaimer.
%% 2. Redistributions in binary form must reproduce the above copyright
%%    notice, this list of conditions and the following disclaimer in the
%%    documentation and/or other materials provided with the distribution.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
%% FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
%% COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
%% INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
%% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
%% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
%% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
%% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
%% ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
%% POSSIBILITY OF SUCH DAMAGE.

%% File    : lfe_io.erl
%% Purpose : Some basic i/o functions for Lisp Flavoured Erlang.
%%
%% The io functions have been split into the following modules:
%% lfe_io        - basic read and write functions
%% lfe_io_pretty - sexpr prettyprinter

-module(lfe_io).

-export([parse_file/1,read_file/1,read/0,read/1,
	 print/1,print/2,print1/1,print1/2,
	 prettyprint/1,prettyprint/2,
	 prettyprint1/1,prettyprint1/2,prettyprint1/3,prettyprint1/4]).

-export([print1_symb/1,print1_string/2,print1_bits/2]).

%% -compile(export_all).

-import(lists, [flatten/1,reverse/1,reverse/2,map/2,mapfoldl/3,all/2]).

%% parse_file(FileName) -> {ok,[{Sexpr,Line}]} | {error,Error}.
%% Parse a file returning the raw sexprs (as it should be) and line
%% numbers of start of each sexpr. Handle errors consistently.

parse_file(Name) ->
    with_token_file(Name, fun (Ts) -> parse_file1(Ts, []) end).

parse_file1(Ts0, Ss) when Ts0 /= [] ->
    case lfe_parse:sexpr(Ts0) of
	{ok,L,S,Ts1} -> parse_file1(Ts1, [{S,L}|Ss]);
	{error,E,_} -> {error,E}
    end;
parse_file1([], Ss) -> {ok,reverse(Ss)}.

%% read_file(FileName) -> {ok,[Sexpr]} | {error,Error}.
%% Read a file returning the raw sexprs (as it should be).

read_file(Name) ->
    with_token_file(Name, fun (Ts) -> read_file1(Ts, []) end).

read_file1(Ts0, Ss) when Ts0 /= [] ->
    case lfe_parse:sexpr(Ts0) of
	{ok,_,S,Ts1} -> read_file1(Ts1, [S|Ss]);
	{error,E,_} -> {error,E}
    end;
read_file1([], Ss) -> {ok,reverse(Ss)}.

with_token_file(Name, Do) ->
    case file:open(Name, [read]) of
	{ok,F} ->
	    case io:request(F, {get_until,'',lfe_scan,tokens,[1]}) of
		{ok,Ts,_} -> Do(Ts);
		{error,Error,_} -> {error,Error}
	    end;
	{error,Error} -> {error,{none,file,Error}}
    end.

%% read([IoDevice]) -> Sexpr.
%%  A very simple read function. Line oriented but can handle multiple
%%  lines. Anything remaining on last line after a sexpr is lost.
%%  Signal errors.

read() -> read(standard_io).
read(Io) ->
    scan_and_parse(Io, []).

scan_and_parse(Io, Ts0) ->
    case io:get_line(Io, '') of
	eof ->
	    %% No more so must take what we have.
	    case lfe_parse:sexpr(Ts0) of
		{ok,_,S,_} -> S;
		{error,E,_} -> exit({error,E})
	    end;
	Cs ->
	    case lfe_scan:string(Cs) of
		{ok,[],_} ->
		    %% Empty line (token free) just go on.
		    scan_and_parse(Io, Ts0);
		{ok,More,_} ->
		    Ts1 = Ts0 ++ More,
		    case lfe_parse:sexpr(Ts1) of
			{ok,_,S,_} -> S;
			{error,{_,_,{missing,_}},_} ->
			    scan_and_parse(Io, Ts1);
			{error,E,_} -> exit({error,E})
		    end;
		E -> exit(E)
	    end
    end.
    
%% print([IoDevice], Sexpr) -> ok.
%% print1(Sexpr) -> [char()].
%% print1(Sexpr, Depth) -> [char()].
%%  A simple print function. Does not pretty-print. N.B. We know about
%%  the standard character macros and use them instead of their
%%  expanded forms.

print(S) -> print(standard_io, S).
print(Io, S) -> io:put_chars(Io, print1(S)).

print1(S) -> print1(S, -1).			%All the way

print1(_, 0) -> "...";
print1(Symb, _) when is_atom(Symb) -> print1_symb(Symb);
print1(Numb,_ ) when is_integer(Numb) -> integer_to_list(Numb);
print1(Numb, _) when is_float(Numb) -> float_to_list(Numb);
%% Handle some default special cases, standard character macros. These
%% don't increase depth as they really should.
print1([quote,E], D) -> [$'|print1(E, D)];	%$'
print1([backquote,E], D) -> [$`|print1(E, D)];
print1([unquote,E], D) -> [$,|print1(E, D)];
print1(['unquote-splicing',E], D) -> [",@"|print1(E, D)];
%%print1([binary|Es]) -> ["#B"|print1(Es)];
print1([E|Es], D) ->
    if D =:= 1 -> "(...)";			%This looks much better
       true ->
	    [$(,print1(E, D-1),print1_tail(Es, D-1),$)]
    end;
print1([], _) -> "()";
print1({}, _) -> "#()";
print1(Vec, D) when is_tuple(Vec) ->
    if D =:= 1 -> "{...}";			%This looks much better
       true ->
	    [E|Es] = tuple_to_list(Vec),
	    ["#(",print1(E, D-1),print1_tail(Es, D-1),")"]
    end;
print1(Bit, _) when is_bitstring(Bit) ->
    ["#B(",print1_bits(Bit),$)];
print1(Other, D) ->				%Use standard Erlang for rest
    io_lib:write(Other, D).

%% print1_symb(Symbol) -> [char()].

print1_symb(Symb) ->
    Cs = atom_to_list(Symb),
    case quote_symbol(Symb, Cs) of
	true -> print1_string(Cs , $|);
	false -> Cs
    end.

%% print1_bits(Bitstring)
%% Print the bytes in a bitstring. Print bytes except for last which
%% we print as bitstring segement if not 8 bits big.

print1_bits(Bits) -> print1_bits(Bits, -1).	%Print them all

print1_bits(_, 0) -> "...";
print1_bits(<<B:8>>, _) -> integer_to_list(B);	%Catch last binary byte
print1_bits(<<B:8,Bits/bitstring>>, N) ->
    [integer_to_list(B),$\s|print1_bits(Bits, N-1)];
print1_bits(<<>>, _) -> [];
print1_bits(Bits, _) ->				%0 < Size < 8
    N = bit_size(Bits),
    <<B:N>> = Bits,
    io_lib:format("(~w bitstring (size ~w))", [B,N]).

%% print1_tail(Tail, Depth)
%% Print the tail of a list. We know about dotted pairs.

print1_tail([], _) -> "";
print1_tail(_, 1) -> " ...";    
print1_tail([S|Ss], D) ->
    [$\s,print1(S, D-1)|print1_tail(Ss, D-1)];
print1_tail(S, D) -> [" . "|print1(S, D-1)].

%% quote_symbol(Symbol, SymbChars) -> bool().
%% Check if symbol needs to be quoted when printed. If it can read as
%% a number then it must be quoted.

quote_symbol(_, [C|Cs]=Cs0) ->
    case catch {ok,list_to_float(Cs0)} of
	{ok,_} -> true;
	_ -> case catch {ok,list_to_integer(Cs0)} of
		 {ok,_} -> true;
		 _ -> not (start_symb_char(C) andalso symb_chars(Cs))
	     end
    end;
quote_symbol(_, []) -> true.

symb_chars(Cs) -> all(fun symb_char/1, Cs).

start_symb_char($#) -> false;
start_symb_char($`) -> false;
start_symb_char($') -> false;			%'
start_symb_char($,) -> false;
start_symb_char($|) -> false;			%Symbol quote character
start_symb_char(C) -> symb_char(C).

symb_char($() -> false;
symb_char($)) -> false;
symb_char($[) -> false;
symb_char($]) -> false;
symb_char(${) -> false;
symb_char($}) -> false;
symb_char($") -> false;				%"
symb_char($;) -> false;
symb_char(C) -> ((C > $\s) and (C =< $~)) orelse (C > $\240).

%% print1_string([Char], QuoteChar) -> [Char]
%%  Generate the list of characters needed to print a string.

print1_string(S, Q) ->
    [Q|print1_string1(S, Q)].

print1_string1([], Q) ->    [Q];
print1_string1([C|Cs], Q) ->
    string_char(C, Q, print1_string1(Cs, Q)).

string_char(Q, Q, Tail) -> [$\\,Q|Tail];	%Must check these first!
string_char($\\, _, Tail) -> [$\\,$\\|Tail];
string_char(C, _, Tail) when C >= $\s, C =< $~ ->
    [C|Tail];
string_char(C, _, Tail) when C >= $\240, C =< $\377 ->
    [C|Tail];
string_char($\n, _, Tail) -> [$\\,$n|Tail];	%\n = LF
string_char($\r, _, Tail) -> [$\\,$r|Tail];	%\r = CR
string_char($\t, _, Tail) -> [$\\,$t|Tail];	%\t = TAB
string_char($\v, _, Tail) -> [$\\,$v|Tail];	%\v = VT
string_char($\b, _, Tail) -> [$\\,$b|Tail];	%\b = BS
string_char($\f, _, Tail) -> [$\\,$f|Tail];	%\f = FF
string_char($\e, _, Tail) -> [$\\,$e|Tail];	%\e = ESC
string_char($\d, _, Tail) -> [$\\,$d|Tail];	%\d = DEL
string_char(C, _, Tail) ->			%Other control characters.
    C1 = hex(C bsr 4),
    C2 = hex(C band 15),
    [$\\,$x,C1,C2,$;|Tail].

hex(C) when C >= 0, C < 10 -> C + $0;
hex(C) when C >= 10, C < 16 -> C + $a.

%% prettyprint([IoDevice], Sexpr) -> ok.
%% prettyprint1(Sexpr, Indentation) -> [char()].
%%  External interface to the prettyprint functions.

prettyprint(S) -> prettyprint(standard_io, S).
prettyprint(Io, S) -> io:put_chars(Io, prettyprint1(S, -1)).

prettyprint1(S) -> lfe_io_pretty:print1(S).
prettyprint1(S, D) -> lfe_io_pretty:print1(S, D, 0, 80).
prettyprint1(S, D, I) -> lfe_io_pretty:print1(S, D, I, 80).
prettyprint1(S, D, I, L) -> lfe_io_pretty:print1(S, D, I, L).
