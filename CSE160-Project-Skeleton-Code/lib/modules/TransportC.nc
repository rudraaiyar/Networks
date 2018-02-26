#include "../../includes/socket.h"

generic configuration TransportC(){
   provides interface Transport;
}

implementation{
   components new TransportP();
   Transport = TransportP.Transport;
   
	components new LongQueueC(pack, SOCKET_BUFFER_SIZE/TCP_PACKET_MAX_PAYLOAD_SIZE*MAX_NUM_OF_SOCKETS) as rcv;
	TransportP.recieveBuf->rcv;
	components new LongQueueC(pack, SOCKET_BUFFER_SIZE/TCP_PACKET_MAX_PAYLOAD_SIZE*MAX_NUM_OF_SOCKETS) as snd;
	TransportP.sendBuf->snd;
	
	//components new QueueC(pack, 10) as testq;
	
	//components new ListC(tcpP,10) as lst; //create a new timer with alias â€œmyTimerCâ€
	//Transport.recieveBuf -> lst; 
    
	components new SimpleSendC(AM_PACK);
    TransportP.Sender -> SimpleSendC;
	
	components new TimerMilliC() as myTimer; //create a new timer with alias â€œmyTimerCâ€
	TransportP.queTimer -> myTimer; //Wire the interface to the component
	
	components LocalTimeMilliC as tim;
	TransportP.now -> tim;
	
}
