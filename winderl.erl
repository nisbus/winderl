%%%-------------------------------------------------------------------
%%% @author nisbus <nisbus@gmail.com>
%%% @copyright (C) 2012, nisbus
%%% @doc
%%%   winderl is for managing windowed streams of data.
%%%   It provides an API for adding data to the window and getting notifications 
%%%   when data expires from the window.
%%%   It also provides calls to get the current window and the current external state.
%%%
%%%   When starting the server you need to give it an update fun to execute on incoming data.
%%%   You can optionally provide it with an expire fun to execute on all expired data.
%%%   The server can also manage state given to you in the start but if you do so you must also
%%%   provide update- and (optionally) expired funs that takes in two arguments to update the external state
%%%   when data arrives or is expired.
%%% @end
%%% Created : 18 Nov 2012 by nisbus <nisbus@gmail.com>
%%%-------------------------------------------------------------------
-module(winderl).

-behaviour(gen_server).

%% API
-export([start_link/4, stream_update/1,current_window/0, external_state/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-type timeframe() :: {integer(), integer(), integer()}.

-record(state, 
	{
	  window_length :: timeframe(),
	  expired_fun :: fun(),
	  update_fun :: fun(),
	  external_state :: any(),
	  current_window :: [],
	  window_length_in_ms :: integer(),
	  check_expired_timer :: reference()
	}).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc
%%  Updates the current window with new data
%% @end
stream_update(Data) ->
    gen_server:cast(?SERVER,{incoming_data,Data}).

%% @doc Returns the data in the current window
current_window() ->
    gen_server:call(?SERVER,current_state).	

%% @doc Returns the data in the current external state
external_state() ->	     
    gen_server:call(?SERVER, external_state).
%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%--------------------------------------------------------------------
-spec start_link(WinSize :: timeframe(), UpdateFun :: fun(), ExpireFun :: fun()|undefined, ExternalState :: any()) -> {ok,pid()}| ignore | {error,Error :: any()}.
start_link(WinSize, UpdateFun,ExpireFun,ExternalState) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [{WinSize, UpdateFun, ExpireFun, ExternalState}], []).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([{WinSize, UpdateFun,ExpireFun,ExternalState}]) ->
    {ok,TRef} = timer:send_interval(1, check_expired),
    {ok, #state
     {
       window_length=WinSize, 
       update_fun= UpdateFun, 
       expired_fun=ExpireFun, 
       external_state=ExternalState, 
       window_length_in_ms = timeframe_to_milliseconds(WinSize),
       check_expired_timer = TRef,
       current_window = []}}.


handle_call(external_state, _From, #state{external_state = ExtState} = State) ->
    {reply, ExtState, State};

handle_call(current_state, _From, #state{current_window = Window} = State) ->
    Out = lists:map(fun({T,D}) ->
			    {calendar:gregorian_seconds_to_date_time(T*1000),D}
		    end, Window),
    {reply, Out, State};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({incoming_data, Data},#state{current_window = W, update_fun=UpdFun, external_state = ExtState} = State) ->
    {NewWindow, NewExtState} = process_new(W, UpdFun,ExtState, Data),
    {noreply,State#state{current_window = NewWindow, external_state = NewExtState}};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @doc
%%    This gets called internally by the timer every millisecond
%% @end
handle_info(check_expired, #state{current_window = W, window_length_in_ms = MS, expired_fun=ExpFun, external_state = ExtState} = State) ->
    {NewWin, NewExtState} = process_expired(W,MS,ExtState,ExpFun),
    {noreply,State#state{current_window = NewWin, external_state = NewExtState}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{check_expired_timer = T} = _State) ->
    case T of
	undefined ->
	    void;
	_ ->
	    timer:exit(T)
    end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%%Internal functions
%%%===================================================================

%% @doc
%%    Returns old items from the current window
%% @end
get_old_data(Data, WinSize) ->
    CurrentTime = now_to_milliseconds(erlang:now()),    
    Expired = CurrentTime-WinSize,
    [{Time,X} || {Time,X} <- Data, Time < Expired].

%% @doc
%%   Removes each expired element and updates the window.
%%   Runs the expiredfun for each expired item and updates the external_state if needed.
%% @end
process_expired(Window, MS, ExtState, ExpFun) ->
    ExpiredData = get_old_data(Window,MS),
    case ExpFun of
	undefined -> 
	    {lists:subtract(Window,ExpiredData),ExtState};
	_ ->
	    lists:foreach(fun({_T,D}) ->
				  case ExtState of
				      undefined ->
					  ExpFun(D),
					  {lists:subtract(Window,ExpiredData),ExtState};
				      _ ->
					  NewExtState = ExpFun(D,ExtState),
					  {lists:subtract(Window,ExpiredData),NewExtState}
				  end
			  end,ExpiredData)
    end.

%% @doc
%%    Adds the new data (with timestamp) to the window.
%%    Runs the UpdateFun and updates the ExternalState if needed.
%% @end
process_new(Window,UpdFun, ExtState, NewData) ->
    Add = {now_to_milliseconds(erlang:now()),NewData},
    NewWindow = lists:append(Window,[Add]),
    case UpdFun of
	undefined ->
	    {NewWindow, ExtState};
	_ ->
	    case ExtState of
		undefined ->		    
		    UpdFun(NewData),
		    {NewWindow, ExtState};
		_ ->
		    NewState = UpdFun(NewData,ExtState),
		    {NewWindow, NewState}
	    end
    end.
    
timeframe_to_milliseconds({Hour, Minute,Sec}) ->
    timeframe_to_milliseconds({Hour,Minute,Sec,0});
timeframe_to_milliseconds({Hour, Minute,Sec,Milliseconds}) ->
    (Hour*3600000)+(Minute*60000)+(Sec*1000)+Milliseconds.
    
%% @doc
%%   Thanks to zaphar for this gist
%%   https://gist.github.com/104903
%% @end
now_to_seconds({Mega, Sec, _}) ->
    (Mega * 1000000) + Sec.   
    
now_to_milliseconds({Mega, Sec, Micro}) ->
    now_to_seconds({Mega, Sec, Micro}) * 1000.
