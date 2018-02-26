#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"


 generic module TransportP(){
   provides interface Transport;
   uses interface SimpleSend as Sender;
   uses interface LongQueue<pack> as recieveBuf;
   uses interface LongQueue<pack> as sendBuf;
   uses interface Timer<TMilli> as queTimer; //Interface that was wired above, only timer
      
   uses interface LocalTime<TMilli> as now;
}

implementation{
	socket_store_t sockets[MAX_NUM_OF_SOCKETS]={{0}};
	uint8_t socketUsed[MAX_NUM_OF_SOCKETS]={0};
	
	
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		Package->protocol = protocol;
		memcpy(Package->payload, payload, length);
	}
	
	command void Transport.init(){
		call queTimer.startPeriodic(10);
	}
	
	
	event void queTimer.fired(){//mod later
		int i;
		int j;
		pack clearer={0};
		pack resp={0};
		tcpP resptcp={0};
		tcpP* tmp= 0;
		pack* tempp;
		socket_store_t* sock;
		while(clearer=(call recieveBuf.front()),((tcpP*)(&clearer.payload))->flags==SATISFIED_FLAG){
			call recieveBuf.dequeue();
		}
		for(i=0;i<call recieveBuf.size();i++){
			tmp = (tcpP*)&((call recieveBuf.getP(i))->payload);
			tempp = call recieveBuf.getP(i);
			for(j=0;j<MAX_NUM_OF_SOCKETS;j++){
					if(sockets[j].src.port==tmp->src&&sockets[j].dest.port==tmp->dest&&\
					tempp->src==sockets[j].src.addr&&tempp->dest==sockets[j].dest.addr){
						sock = &sockets[j];
					}
			}
			switch(tmp->flags){
				
				case DATA_FLAG :
					if(sock->effectiveWindow-TCP_PACKET_MAX_PAYLOAD_SIZE>=0){
						resptcp.src=tmp->dest;
						resptcp.dest=tmp->src;
						resptcp.seq=tmp->seq;
						resptcp.ack=tmp->ack;
						resptcp.flags=DATA_ACK_FLAG;
						resptcp.advertised_window=sock->effectiveWindow-TCP_PACKET_MAX_PAYLOAD_SIZE;
						sock->effectiveWindow-=TCP_PACKET_MAX_PAYLOAD_SIZE;
						resptcp.timeStamp=call now.get();
						makePack(&resp,TOS_NODE_ID,sock->dest.addr,MAX_TTL,1,TCP,&resptcp,PACKET_MAX_PAYLOAD_SIZE);
						dbg(GENERAL_CHANNEL,"Node %d port %d recieved a TCP packet: %s",TOS_NODE_ID,sockets[j].src.port,tempp->payload);
						//consume the packet with an application
					}
				break;
				
				
				
				case DATA_ACK_FLAG :
				for(j=0;j<call sendBuf.size();j++){
					if(((tcpP*)&((call recieveBuf.getP(i))->payload))->seq==tmp->ack){
						((tcpP*)&((call recieveBuf.getP(i))->payload))->flags=SATISFIED_FLAG;
						break;
					}
				}
				break;
				
				case SYN_FLAG :
					if(sock->state=CLOSED){
						resptcp.src=tmp->src;
						resptcp.dest=tmp->dest;
						resptcp.seq=tmp->seq;
						resptcp.ack=tmp->ack;
						resptcp.flags=SYN_ACK_FLAG;
						resptcp.timeStamp=call now.get();
						makePack(&resp,TOS_NODE_ID,sock->dest.addr,MAX_TTL,1,TCP,&resptcp,PACKET_MAX_PAYLOAD_SIZE);
						dbg(GENERAL_CHANNEL,"Node %d port %d recieved a TCP packet: %s",TOS_NODE_ID,sockets[j].src.port,tempp->payload);
						call sendBuf.enqueue(resp);
						//consume the packet with an application
					}
				break;
				
				case SYN_ACK_FLAG :
					if(sock->state=SYN_SENT){
						resptcp.src=tmp->src;
						resptcp.dest=tmp->dest;
						resptcp.seq=tmp->seq;
						resptcp.ack=tmp->ack;
						resptcp.flags=ACK_FLAG;
						resptcp.timeStamp=call now.get();
						makePack(&resp,TOS_NODE_ID,sock->dest.addr,MAX_TTL,1,TCP,&resptcp,PACKET_MAX_PAYLOAD_SIZE);
						dbg(GENERAL_CHANNEL,"Node %d port %d recieved a TCP packet: %s",TOS_NODE_ID,sockets[j].src.port,tempp->payload);
						call sendBuf.enqueue(resp);
						sock->state=SYN_RCVD;
						//consume the packet with an application
					}
				break;
				
				case ACK_FLAG :
					if(sock->state=SYN_RCVD){
						dbg(GENERAL_CHANNEL,"Node %d port %d recieved a TCP packet: %s",TOS_NODE_ID,sockets[j].src.port,tempp->payload);
						sock->state=ESTABLISHED;
						//consume the packet with an application
					}
				break;
				
				case FIN_FLAG :
					if(sock->state=ESTABLISHED){
						resptcp.src=tmp->src;
						resptcp.dest=tmp->dest;
						resptcp.seq=tmp->seq;
						resptcp.ack=tmp->ack;
						resptcp.flags=ACK_FIN_FLAG;
						resptcp.timeStamp=call now.get();
						makePack(&resp,TOS_NODE_ID,sock->dest.addr,MAX_TTL,1,TCP,&resptcp,PACKET_MAX_PAYLOAD_SIZE);
						dbg(GENERAL_CHANNEL,"Node %d port %d recieved a TCP packet: %s",TOS_NODE_ID,sockets[j].src.port,tempp->payload);
						//consume the packet with an application
					}
				break;
				
				case ACK_FIN_FLAG :
					if(sock->state=ESTABLISHED){
						resptcp.src=tmp->src;
						resptcp.dest=tmp->dest;
						resptcp.seq=tmp->seq;
						resptcp.ack=tmp->ack;
						resptcp.flags=ACK_FIN_FLAG;
						resptcp.timeStamp=call now.get();
						makePack(&resp,TOS_NODE_ID,sock->dest.addr,MAX_TTL,1,TCP,&resptcp,PACKET_MAX_PAYLOAD_SIZE);
						dbg(GENERAL_CHANNEL,"Node %d port %d recieved a TCP packet: %s",TOS_NODE_ID,sockets[j].src.port,tempp->payload);
						sock->state=CLOSED;
						//consume the packet with an application
					}
				break;
			}
		}
	}
	
	   command socket_t Transport.socket(){
	   		//initializes all values
			socket_t ret;
	   		uint16_t i;
			socket_store_t * skt=0;
			
			for(ret=1;ret<MAX_NUM_OF_SOCKETS;ret++){
				if(!socketUsed[ret]){
					skt=&sockets[ret];
					socketUsed[ret]=1;
					break;
				}
			}
			
			if(skt){
				// initialize all values in socket store
				skt-> flag =0;
				skt->state=CLOSED; //close it until syn and est
				skt-> src.addr=0;
				skt-> src.port=0;
				skt-> dest.addr=0;
				skt-> dest.port=0; //linked to socket_add_t which has some issue with type

				// This is the sender portion.
				skt-> lastWritten=0;
				skt-> lastAck=0;
				skt-> lastSent=0;

				// This is the receiver portion
				skt-> lastRead=0;
				skt-> lastRcvd=0;
				skt-> nextExpected=0;

				skt-> RTT=0;
				skt-> effectiveWindow=0;
				
				for (i = 0; i < SOCKET_BUFFER_SIZE; i++){
					skt->rcvdBuff[i] = 0;
					skt->sendBuff[i] = 0;
				}
			}else{
				return 0;
			}			
			return ret;
	   }

	   command error_t Transport.bind(socket_t fd, socket_addr_t *addr){
	   		//binds the src addr to the socket
	   		sockets[fd].src.addr = addr->addr;
			sockets[fd].src.port = addr->port;
			sockets[fd].state = LISTEN;	// change state to closed
			
			return 0;
	   }

	   command socket_t Transport.accept(socket_t fd){
			//call when server established a connection
			//something here that enforces that
			return fd;
	   		
	   }

	   command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen){
	   		uint16_t i=0;
			pack store;
			tcpP send={0};
			socket_store_t* sock = &sockets[fd];
			//write to socket from buffer
			if(!socketUsed[fd]) return 0;
			for(i=0;i<bufflen;i+=TCP_PACKET_MAX_PAYLOAD_SIZE-1){
				send.dest=sock->dest.port;
				send.src=sock->src.port;
				send.flags=DATA_FLAG;
				send.seq=++(sock->lastSent);
				memcpy(send.payload,&buff[i],TCP_PACKET_MAX_PAYLOAD_SIZE-1);
				makePack(&store,sock->dest.addr,sock->src.addr,MAX_TTL,1,TCP,&send,PACKET_MAX_PAYLOAD_SIZE);
				if(call sendBuf.enqueue(store)){
					return i;
				}
			}
	   }


	   command error_t Transport.receive(pack* package){
			return SUCCESS;
	   }


	   command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){
	   		//read from socket, write data to buffer
			dbg(GENERAL_CHANNEL, "adding to %d: %d,%d\n",fd,call recieveBuf.size(),call now.get());
	   }


	   command error_t Transport.connect(socket_t fd, socket_addr_t * addr){
			//closes the socket after successful connection and sends out syn pack
	   		pack p;	
			tcpP* t; //tcp packet 
			socket_store_t* currS; //current socket position
			
			t = (tcpP*) p.payload; //use t as p payload
			
			// create SYN for tcp
			t->dest = sockets[fd].dest.port; //wtf at this stupid port
			t->src = sockets[fd].src.port;
			t->seq = 0; //or even a random number?
			t->ack = 0; //no acks when syn just yet
			t->flags = SYN_FLAG; //2
			t->advertised_window = SOCKET_BUFFER_SIZE; //buffer size
			
			//makepack
			//makePack(&p, TOS_NODE_ID, sockets[fd].dest.addr, MAX_TTL, PROTOCOL_TCP, 0, t, 0); 
			//send out
			call Sender.send(p, sockets[fd].dest.addr);
		
			//update all values in socket_store_t addressing
			currS = &sockets[call Transport.socket()];
			currS->state = SYN_ACK_FLAG;
			currS->dest.addr = sockets[fd].dest.addr;
			currS->dest.port = sockets[fd].dest.port;
			currS->src.addr = TOS_NODE_ID;
			currS->src.port = sockets[fd].src.port;
			
			//store this somewhere too
	   }


	   command error_t Transport.close(socket_t fd){
	   //change state to closed
	   		//fd.state = CLOSED;
			return 0;
	   }


	   command error_t Transport.release(socket_t fd){
	   		//fd.state = CLOSED;
			
			return fd;
	   
	   } //gives error for some reason go back and check for T.nc

	   command error_t Transport.listen(socket_t fd){
	   //change state to listen
	   if(sockets[fd].state == CLOSED){
			sockets[fd].state=LISTEN;
			return SUCCESS;
	   }
	   return FAIL;
	   }
   
}