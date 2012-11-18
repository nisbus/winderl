winderl
=======

windowed streams in erlang  
  
winderl is for managing windowed streams of data.  
It provides an API for adding data to the window and getting notifications  
when data expires from the window.  
  
It also provides calls to get the current window and the current external state.  
When starting the server you need to give it an update fun to execute on incoming data.  
You can optionally provide it with an expire fun to execute on all expired data.  
The server can also manage state given to you in the start but if you do so you must also  
provide update- and (optionally) expired funs that takes in two arguments to update the external state  
when data arrives or is expired.  
  
This could be useful for instance for running calculations of windowed data such as a 5 minute average for  
a stream of data etc.  
  
Example:  
  
Start the server with a window length of one minute and print out data as it arrives and again when it expires.  
```erlang  
winderl:start_link({0,1,0}, fun(X) -> io:format("Data received: ~p~n",[X]) end, fun(X) -> io:format("Data expired: ~p~n",[X]) end, undefined,100).
```  
  
```erlang  
winderl:update("First data inserted").
```  
  
Now you should see "Data received: First data inserted" printed on the console and  
"Data expired: First data inserted" a minute later.  
  
