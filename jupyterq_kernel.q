/ jupyter kernel, no code or data lives here, communicates with a server proces but handles jupyter zeromq messaging
\p 0W   / need for server process to connect
\l p.q
\d .qpk
\l jupyterq_pyzmq.q / zero mq messaing

/ common variables
opts:first each .Q.opt .z.x                            / command line args (kernel cmdline args)
dlm:"<IDS|MSG>"                                        / delimitter between zmq identities and message content
dd:(0#`)!()                                            / default dict
exn:-1                                                 / execution count
sid:string first -1?0Ng                                / session id for kernel
allowstop:1b;                                          / allow shutdown by client
cds:.j.k"c"$read1 hsym`$opts`cds                       / connection details
fd2s:(0#0i)!0#0                                        / file descriptor (int) -> 0mq socket (long)
s2n:(0#0)!0#`                                          / 0mq socket to name
socks:0#0                                              / open zmq socks
deb:$[`debug in key opts;"B"$opts`debug;0b]            / debug put debug = 1b in kernel.json for debug messages
/ 0mq ports
cports:`sh`io`si`cn`hb!string"j"$cds`shell_port`iopub_port`stdin_port`control_port`hb_port

/ general utils
sstring:{$[10=type x;;string]x}                        / string convert, or leave char[] alone
fexists:{x~key x:hsym`$sstring x}                      / file exists
dexists:{11=type key hsym`$sstring x}                  / directory exists
logdeb:{if[deb;0N!x];x};                               / debug
ts:{@[string .z.p;4 7 10;:;"--T"],"Z"}                 / ISO 8601 UTC timestamp
df:{x k?[;y]k:key x}                                   / helper, return entry at ` for a dict of funcs if y not present
acb:`:./jupyterq 2:`acb,1                              / add callback to q, calling cb below
rcb:`:./jupyterq 2:`rcb0x,2                            / remove callback from q
cb:{$[x in key fd2s;zcb x;x in stdfd;stdcb x;]}        / call correct callback for socket
md:{(1#x)!1#y}                                         / make one item dict
.z.exit:{cleanz`;cleans`}                              / clean zeromq sockets and server process before exit
.z.pc:{if[x~neg srvh;exit 2]}                          / server exited (change if ever supports connection to running servers)
fmterr:{$[0=type x;.z.s'[x];"\033[0;31m",x,"\033[0m"]} / put color codes (as unicode) round text for error display
starterr:{-2 x;exit 1;}                                / error on startup

/ for split into kernel and execution server
stdn:1 2i!key stdfd:`stdout`stderr!2#0Ni;
rfd:{if[not count r:read1 x;rcb[x;1b]];r}              / read, if socket closed remove it with sd0x(fd,1)
rstd:{r:0#0x0;while[not 0~b:@[rfd;x;0];r,:b];r}        / read all available from socket
regstd:{stdfd[stdn x]:fd:.z.w;rcb[fd;0b];acb fd}       / register fd as a stdout/err redirection
stdcb:{if[count[srvq]&count o:rstd x;snd[();io]        / callback when stdout/err received from server, x is fd
 kr[`stream;srvq[0;2]]`name`text!(stdfd?x;"c"$o)]}
sndstd:{{if[count o:rstd stdfd y;snd[();io]            / read all available stdout/err and publish
  kr[`stream;x]`name`text!(y;"c"$o)]}[x]'[stdn]}
srvq:()                                                / holds queue of zids,sockets and msgs, for use in fifocb
srvqdrop:{srvq::1 _ srvq}                              / drop a tuple of (zmqids;socket;messagecontent) from queue
srvh:0N                                                / execution server's handle
sndsrv:{$[null srvh;pend;srvh]x}                       / queue or send command to server
srvexec:{[f;z;s;mc]sndsrv(`.qpk.execmsg;f;z;s;mc)}     / exec a request on the server
pending:()                                             / pending commands for server as it starts up
pend:{pending,:enlist x}                               / queue a command to the server
srvreg:{srvh::neg .z.w;srvh each pending;pending::()}  / server registration, exec all pending messages
srvstarterr:{starterr` sv("server startup error";x;y)} / execution server startup error
cleans:{@[hclose;;{}]each stdfd}                       / clean up redirected sockets if not done already
/ start server, windows uses named pipes, mac linux use sockets
if[.z.o like"w*";
 npcreate:`:./jupyterq 2:`npcreate,1; / TODO name?
 startsrv:{ / x is string port
  stdfd[`stdout;stderr]:npcreate each`$oe:{"\\\\.\\pipe\\jupyterq_",""sv string x,1?0Ng}each`out`err;
  system"start /B cmd /C q jupyterq_server.q -q ",x," ",getenv[`JUPYTERQ_SERVERARGS]," ^>",oe[0]," 2^>",oe 1};
 .z.ts:{stdcb each stdfd;};system"t 50";]; / TODO can we select on named pipe
if[not .z.o like"w*";
 startsrv:{system"q jupyterq_server.q -q ",x," ",getenv[`JUPYTERQ_SERVERARGS]}];

/ 0mq socket management
cleanz:{{rcb[zsock.fd x;0b];zsock.destroy x}'[socks]}  / clean up sockets, we're about to exit
/ setup sockets and add callbacks through sd1
{[t;x]x set last socks,:zsock[t][`$cds.transport,"://",cds.ip,":",cports x]}''[`new_router`new_pub;(`sh`si`cn`hb;`io)];
{[x]fd2s[fd:zsock.fd x]:x:value sx:x;s2n[x]:sx;acb fd}'[`sh`si`cn`hb];

/ kernel responses and send functions
krd:`header`pheader`metadata`content!4#enlist dd       / kernel default response (everything empty)
kri:{[k;v]@[krd;k;:;v]}                                / override defaults with provided values
kr:{[mtyp;p;c]                                         / kernel response from msgtype, parent msg, content dict
 kri[`header`pheader`content;(krh mtyp;p`header;c)]}
krh:{`version`date`session`username`msg_type`msg_id!   / new kernel response header for messages from msg_type
 (`5.1;ts[];sid;.z.u;x;rand 0Ng)}
sndstat:{snd[();io]kr[`status;y]md[`execution_state]x} / send status x with parent message y
snd:{[z;s;mcr]                                         / send a message to a socket with content mcr
 zmsg.addC[msg:zmsg.new`]'[sm[z]logdeb mcr];zmsg.send[msg]s}
idle:{srvqdrop sndstat[`idle]x}                        / update status to idle and drop parent message from the server q

/ signing
sig:.p.import[`hmac]`:new                              / hmac as foreign
hmac:{                                                 / hmac as char[]
 sig["x"$cds.key;`msg pykw"x"$x;
  `digestmod pykw`SHA256][`:hexdigest;<][]}
sm:{[z;md]z,(dlm;hmac raze js),js:value json each md}  / sign message, given zmq ids and message dicts
json:{ssr[.j.j x;"\033";"\\u001b"]}                    / NOTE octal escapes aren't converted to \uNNNN by .j.j in .z.K<3.6, not doing properly here, just the one I want \033

/ code parsing
/ this is 'script like' execution of code x by function y, used here to check parsing
k)l:{r@&~(::)~'r:y{x y}'"\n"/:'x(&|1^\|0N 0 1"/ "?*:'x[i],'"/")_i:&~|':(b?-1)#b:+\-/(x:$[@x;`\:;]x)~\:/:+,"/\\"}

prse:{$[")"=x 1;$[flang x;1;"\\"=x 2;1;-5!x];parse x]} / like q.parse but allow q)\syscmd, used for parsing only not during evaluation, can have k)q)q)k)... but don't parse foreign langs
flang:{$[-7=type x;x;")"~x 1;$[x[0]in"qk";2_x;1];0]}/  / there's a foreign language
ep:l[;{@[(0;)@prse@;x;{(1;x)}]}]                       / check parsing

/ main callback on fd, read all available then pop char[]'s from each. For each message (except hbs) we have
/ ({zmqidents};"<IDS|MSGS>";hmacsig;header;parentheader;metadata;content;{extradata...})
/ everything after the hmacsig should be deserializable json dicts (as strings)
zcb:{
 msgs:0#x:fd2s x;
 / recv all available on socket, *must* be everything so callback is invoked next time
 while[not(::)~last msgs:msgs,zmsg.recvnowait x;];
 / action each message for the channel
 {[x;m].[h s2n x;(x;m;s2n x);{-2"error:\n",.Q.sbt y}]}'[x;-1_msgs];
 }

/ channel handlers
h.hb:{[s;m;n]zmsg.send[m;s]} / heartbeats just echo
h.sh:{[s;m;n]
 / read messages and check signatures
 if[not c[di+1]~hmac raze 4#(2+di:c?dlm)_c:zmsg.popC each zmsg.size[m]#m;-2"Invalid message, ignoring";:()];
 / message dicts as dict passed to the request handler
 sndstat[`busy]mc:`header`pheader`metadata`content!.j.k each 4#(2+di)_c;
 mc[`buffers]:(6+di)_c;
 / msg_type specific handling
 r:df[ch.sh;`$mc .`header`msg_type][di#c;s]mc;zmsg.destroy m;
 if[not 0b~r;sndstat[`idle;mc]]; / only send finished if not waiting for server callback
 }
h.si:h.cn:h.sh / control and stdin we treat like shell as there's one thread for everyone

/ channel/msg_type specific request handlers
ch.sh.kernel_info_request:{[z;s;mc]
 reply:select protocol_version:`5.1,implementation:`qpk,implementation_version:`0.0.1,
  banner:("KDB+ v",string[.z.K]," ",string[.z.k]," kdb+ kernel for jupyter v 0.0.1"),help_links:enlist`text`url!("kdb+ help";"http://code.kx.com"),
  language_info:(select name:`q,version:(string[.z.K],".0"),mimetype:"text/x-q",file_extension:`.q from .qpk.dd) from dd;
 :snd[z;s]kr[`kernel_info_reply;mc;reply];
 }

ch.sh.is_complete_request:{[z;s;mc]
 es:(epr:ep mc .`content`code)[;0];
 / hanging {[ and continued select/update/delete allowed but not }"] and only on last line of input
 i:string["[{"],enlist"from";
 :snd[z;s]kr[`is_complete_reply;mc]`status`indent!(;" ")$[any es;`invalid`incomplete(last[epr][1]in i)&all 0=-1_es;`complete];
 }

/ check parsing, append z,s and mc to srvq, then pass to server and return false if no parse error to wait for server response
ch.sh.execute_request:{[z;s;mc]
 es:(epr:ep(mcc:mc`content)`code)[;0]; / first check parsing
 if[any epr[;0];                       / couldn't parse, send back error reply and content
  reply:update traceback:(ename;evalue)from
   select status:`error,execution_count:.qpk.exn,ename:.qpk.fmterr"parse error",evalue:.qpk.fmterr epr[;1]first where es from dd;
  :snd[z]'[io,s;kr[;mc;]'[`error`execute_reply;(delete execution_count,status from reply;reply)]]; / complete as there was an error
 ];
 srvq,:enlist(z;s;mc);
 srvexec[`execute;z;s;mc];
 :0b; / here we do want to remain 'busy' until server has completed
 }

/ code completion and inspection, handled on server
ch.sh.complete_request:srvexec`complete
ch.sh.inspect_request:srvexec`inspect

ch.sh.shutdown_request:{[z;s;mc]if[last allowstop;snd[z;s]kr[`shutdown_reply;mc]md[`restart]mc .`content`restart;exit 0]}
ch.sh.input_reply:{[z;s;mc]srvsi mc .`content`value;}  / pass back front end reply to waiting server

/ comms, all comms are owned and managed by execution server, just pass through to the server
/ frontend->server
ch.sh[`comm_info_request`comm_open`comm_msg`comm_close]:
 {[t;z;s;mc]srvq,:enlist(z;s;mc);srvexec[t;z;s;mc]}@'`comm_info`comm_open`comm_msg`comm_close
/ server->frontend
sndcomm.gen:{[t;f;z;p;c;m;b]snd[z;io]update metadata:m from kr[t;p]{y!x y}[c]f;}
sndcomm.open:sndcomm.gen[`comm_open]`comm_id`target_name`data
sndcomm.msg:sndcomm.gen[`comm_msg]`comm_id`data
sndcomm.close:sndcomm.gen[`comm_close]`comm_id`data

/ch.sh.history_request:{[z;s;mc]} / TODO, not used by notebooks but used by console
/ unknown messages
ch.sh[`]:{[z;s;mc].j.DEBU:mc;-2"Unrecognized message type ",mc[`header][`msg_type]," on channel ",string s2n s}

/ a result from the server
srvres:{[z;s;mc;res]
 sndstd mc;                    / pending stdout/err msgs sent first
 if[mc . `content`silent;:()]; / return early if silent
 err:res 0;exn::res 2;res@:1;  / results, res has (error;result;srvexeccount)
 / send actual content reply through io channel
 snd[z;io]$[err;
  kr[`error;mc]`ename`evalue`traceback!fmterr each (res 0;res 0;("evaluation error:\n";res 0;""),res 1);
  kr[`execute_result;mc]`execution_count`metadata`data!(exn;dd;res)];
 }
/ a result from the server to be displayed with display_data
srvdis:{[z;s;mc;res]
 err:res 0;exn::res 2;res@:1;  / results, res has (error;result;srvexeccount)
 / send actual content reply through io channel
 snd[z;io]$[err;
  kr[`error;mc]`ename`evalue`traceback!fmterr each (res 0;res 0;("evaluation error:\n";res 0;""),res 1);
  kr[`display_data;mc]`metadata`data`transient!(res 1;res 0;dd)];
 }
srvclear:{[z;s;mc;res]snd[z;io]kr[`clear_output;mc]md[`wait]res}
srvinput:{[z;s;mc;prompt;pass]
 if[not mc . `content`allow_stdin;neg[.z.w](1;"Input requests not supported by this frontend");:()];
 snd[z;si]kr[`input_request;mc]`prompt`password!(prompt;pass);}

srvcmp.execute:{[z;s;mc;res]   / server has completed execute_request
 sndstd mc;                    / pending stdout/err msgs sent first
 / return early if silent
 if[mc . `content`silent;:idle mc];
 err:res 0;exn::res 2;res@:1;  / results, res has (error;result;srvexeccount)
 / prep the execution reply or error
 reply:`status`execution_count!(`ok`error err;exn);
 if[err;logdeb(`error;res);reply,:`ename`evalue`traceback!fmterr each(res 0;res 0;("evaluation error:\n";res 0;""),res 1)];
 snd[z;s]kr[`execute_reply;mc]reply;
 idle mc;
 }

srvcmp.complete:{[z;s;mc;res]  / server has completed complete_request
 ce:first res[1],mc .`content`cursor_pos;
 cs:first res[0],mc .`content`cursor_pos;
 snd[z;s]kr[`complete_reply;mc]`matches`cursor_start`cursor_end`metadata`status!(res 2;cs;ce;dd;`ok);
 sndstat[`idle]mc}

srvcmp.inspect:{[z;s;mc;res]   / server has completed inspect_request
 snd[z;s]kr[`inspect_reply;mc]`status`found`data`metadata!(`ok;not res~();res;dd);
 sndstat[`idle]mc}

cmploadsave:{[t;z;s;mc;res]    / server completed load or save command
 sndstd mc;
 if[mc .`content`silent;:idle mc];
 err:res 0;exn::res 2;res@:1;  / results, res has (error;result;srvexeccount)
 reply:`status`execution_count!(`ok`error err;exn);
 if[err;logdeb(`error;res);snd[z;io]kr[`error;mc]reply,:`ename`evalue`traceback!fmterr each(res 0;res 0;(t," error:\n";res 0;"";res 1))];
 if[not[err]and t~"loadscript";reply,:enlist[`payload]!enlist enlist `source`text`replace!(`set_next_input;res .`content`code;1b)];
 snd[z;s]kr[`execute_reply;mc]reply;
 idle mc;
 }
srvcmp.loadscript:cmploadsave"loadscript"              / loaded a script through /%loadscript, won't process just display the new cell to user
srvcmp.savescript:cmploadsave"savescript"              / saved a script through /%savescript, won't process just display result of save
srvcmp.comm_info:{[z;s;mc;res]sndstd mc;snd[z;s]kr[`comm_info_reply;mc]res;idle mc}
srvcmp.commdef:{[z;s;mc;res]idle mc}                   / default completion action for comm messages

/ TODO check all required packages can be imported somehow (even if import kx_backend inline fails..
setenv[`PYTHONPATH]":;"[.z.o like"w*"]sv getenv each `PYTHONPATH`QHOME;
/ check kx backend can be imported, if not may be because zlib (and maybe others) are opened by q before distribution specific ones, preload if so
if[0~@[.p.import;`kxpy.kx_backend_inline;0];
 pre:{setenv[x]$[fexists a:.p.import[`sysconfig;`:get_config_var;<][`LIBDIR],"/",u;a,":";""],(u:.p.import[`ctypes.util;`:find_library;<]y),":",getenv x;};
 $[.z.o like"l*";pre[`LD_PRELOAD]`z;
   .z.o like"m*;pre[`DYLD_INSERT_LIBRARIES]`z;
   .z.o like"w*;'`nyi_win;'`nyi]];
startsrv string system"p"


\
see http://jupyter-client.readthedocs.io/en/latest/messaging.html for details of requests and responses required

/ <action>_request should do this ...
 ch message
 ------------------------------------------------------
 io status: busy
 sh <action>_reply
 io <action>_result (see also display)  if successful
 io error 				if unsuccessful
 io status: idle
