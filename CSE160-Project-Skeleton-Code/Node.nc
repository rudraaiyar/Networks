/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
//#include "lib/modules/TransportP.nc"

#define TIME_TO_LIVE 15 //TTL is 15
#define MAX_NODES 30 //max nodes

typedef struct uniquePacket{ //unique identifiers
	uint16_t src;
	uint16_t seq;
} uniquePacket;

typedef struct routeEntry{ //link state routing information
	uint16_t cost;
	uint16_t nextHop;
} routeEntry;


module Node{
   uses interface Boot;
	
   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;
   
   uses interface Timer<TMilli> as periodicTimer; //Interface that was wired above, only timer

	uses interface Transport;
}

implementation{


   int numNeighbors=0; //number of neighbors
   int refresh = 0; //refresh with timer
   pack sendPackage;
   //uint8_t neighbors[8192]={0};
   uint8_t globalNeighbors[MAX_NODES][8192]={{0}}; //tos node id, neighbors
   routeEntry routingTable[MAX_NODES]={{0}}; //routing table
   uint16_t thisSeq = 0; //sequence counter for that node
   uniquePacket packMemory[TIME_TO_LIVE*TIME_TO_LIVE]; //sub for list via array
   uint8_t memoryFilled = 0; //flag for restrarting packmemory
   pack nilPack; //null value
   int nextpack = 0; //index of the last added packet to the dupicate list
   
	
   
    void setNeighbor(uint8_t list[8192], uint16_t n){
        list[n/8] |= 1<<(n%8);
    }

    void clearNeighbor(uint8_t list[8192], uint16_t n){
        list[n/8] &= ~(1<<(n%8));
    }

    uint8_t getNeighbor(uint8_t list[8192], uint16_t n){ //n is node 
        return !!((list[n/8]>>(n%8)) & 1);
    }
	
	uint16_t countNeighbors(uint8_t list[8192]){
		int i=0;
		uint16_t n=0;
		for(i=0;i<8192;i++){
			if(getNeighbor(list,i))n++;
		}
		return n;
	}

	uint16_t countNodes(uint8_t lists[MAX_NODES][8192]){
		int i=0,j=0;
		uint8_t exist[8192]={0};
		for(i=0;i<MAX_NODES;i++){
			for(j=0;j<8192;j++){
				exist[j]|=lists[i][j];
			}
		}
		return countNeighbors(exist);
	}

	typedef struct hop{

		uint8_t visited;
		uint16_t id;
		uint16_t dist;
		struct hop* prev;

	} hop;

	void dj(uint8_t lists[MAX_NODES][8192]){
		uint16_t nodeCount = countNodes(globalNeighbors)-1;
		hop hops[nodeCount];
		hop source = {1,TOS_NODE_ID,0,0};
		int i=0,j=0,k=0,done=0;
		uint8_t exist[8192]={0};
		hop* min = &hops[0];
		hop* bt = 0;
		//memset(hops,0,sizeof(hops));
		for(i=0;i<MAX_NODES;i++){
			for(j=0;j<8192;j++){
				exist[j]|=lists[i][j];
			}
		}
		clearNeighbor(exist,TOS_NODE_ID);
		for(i=0;i<nodeCount;i++){
			hops[i].visited=0;
			hops[i].id=0;
			hops[i].dist=(uint16_t)65535;
			hops[i].prev=0;
		}
		k=0;
		for(i=0;i<65536;i++){
			if(getNeighbor(exist,i)){
				hops[k].id=i;
				if(getNeighbor(lists[TOS_NODE_ID],i)){
					hops[k].dist=1;
					hops[k].prev=&source;
				}
				k++;
			}
		}
		//dbg(GENERAL_CHANNEL, "Inited dij on node %d, total nodes = %d:%d\n",TOS_NODE_ID,nodeCount,countNeighbors(exist));
		while(1){
			done=1;
			for(i=0;i<nodeCount;i++){
				if(!hops[i].visited){
					done=0;
				}
				if(!hops[i].visited&&(min->visited||hops[i].dist<min->dist)){
					min=&hops[i];
				}
			}
			min->visited=1;
			if(done) break;

			for(j=0;j<nodeCount;j++){
				//if(getNeighbor(lists[min->id],hops[j].id))dbg(GENERAL_CHANNEL, "%d is a neighbor of %d , %d\n",hops[j].id,min->id,countNodes(globalNeighbors));
				if(&hops[j]!=min&&getNeighbor(lists[min->id],hops[j].id)&&hops[j].dist>min->dist+1){
					hops[j].dist=min->dist+1;
					hops[j].prev=min;
					//dbg(GENERAL_CHANNEL, "found a good path through%d\n",min->id);
				}
			}
		}
		
		//dbg(GENERAL_CHANNEL, "Finished dij on node %d\n",TOS_NODE_ID);
		
		for(i=0;i<nodeCount;i++){
			//dbg(GENERAL_CHANNEL, "BTing %d on node %d\n",hops[i].id,TOS_NODE_ID);
			//dbg(GENERAL_CHANNEL, "%d->",hops[i].id);
			bt = &hops[i];
			while(bt->prev!=&source&&bt->prev!=0){
				//dbg(GENERAL_CHANNEL, "%d->",bt->prev);
				bt=bt->prev;
			}
			//dbg(GENERAL_CHANNEL, "%d:%d->\n",(bt->prev?bt->prev->id:0),hops[i].prev);
			routingTable[hops[i].id].nextHop=bt->id;
			routingTable[hops[i].id].cost=bt->dist;
		}
		//dbg(GENERAL_CHANNEL, "Really finished dij on node %d\n",TOS_NODE_ID);
	}
	//encodes string to add characters in between
	void encode(uint8_t buffer[16385], uint8_t list[8192]){ 
		int i=0;
		memset(buffer,0,16385);
		for(i=0;i<PACKET_MAX_PAYLOAD_SIZE-1;i++){
			if(list[i]!=0){
				buffer[2*i]='0';
				buffer[2*i+1]=list[i];
			}else{
				buffer[2*i]=1;
				buffer[2*i+1]='0';
			}
		}
	}
	//takes out the characters added in encode
	void decode(uint8_t buffer[16385], uint8_t list[8192]){
		int i=0;
		memset(list,0,8192);
		for(i=0;i<PACKET_MAX_PAYLOAD_SIZE-1;i++){
			if(buffer[2*i]=='0'){
				list[i]=buffer[2*i+1];
			}else{
				list[i]=0;
			}
		}
	}
	
	uint32_t spaceCalc(){ //calcs string to print neighbor list
		int ret = 0,i;
		char buffer[8] = {0};
		for(i=0;i<sizeof(globalNeighbors[TOS_NODE_ID])*8&&numNeighbors;i++){
			if(getNeighbor(globalNeighbors[TOS_NODE_ID], i)) ret+=sprintf(buffer,"%d,",i);
		}
		return ret;
	}
   
	int checkDuplicate(pack* p){ //checks for duplicates within array
		int i;
		for(i=0;i<(memoryFilled?sizeof(packMemory)/sizeof(uniquePacket):nextpack);i++){
			if(packMemory[i].src==p->src&&packMemory[i].seq==p->seq){
				return 1;
			}
		}
		return 0;
	}
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length); 
    void setTestClient(uint16_t dest, uint16_t srcPort, uint16_t destPort, uint16_t transfer);
	void setTestServer(uint16_t port);
   
   event void Boot.booted(){
	  int primes[] = {11,13,17,19,23,29,31,37,41,43,47}; //for timer
	  int i=0;
	  
	  call AMControl.start();
		
		memset(packMemory,0,sizeof(packMemory)); //sets it to 0
		memset(&nilPack,0,sizeof(pack));
		for(i=0;i<sizeof(routingTable)/sizeof(routeEntry);i++){
			routingTable[i].cost=65535;
			routingTable[i].nextHop=0;
		}
		for(i=0;i<MAX_NODES;i++){
			memset(globalNeighbors[i],0,8192);
		}
		call Transport.init();
		call periodicTimer.startPeriodic(10*primes[rand()%sizeof(primes)/sizeof(int)]*primes[rand()%sizeof(primes)/sizeof(int)]);
		
      dbg(GENERAL_CHANNEL, "Booted \n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){	  
	  tcpP* recvtcp=0;
	  int i=0;
	  if(((pack*) payload)->TTL<=0) return msg;

	  if(((pack*) payload)->protocol!=TCP&&checkDuplicate((pack*) payload)){
		dbg(FLOODING_CHANNEL, "Duplicate ignored %d\n",nextpack);
		return msg;
	  }else{
		dbg(FLOODING_CHANNEL, "Non-Duplicate Packet Received\n");
		packMemory[nextpack].src=((pack*)payload)->src;
		packMemory[nextpack].seq=((pack*)payload)->seq;
		nextpack++;
		nextpack%=sizeof(packMemory)/sizeof(uniquePacket);
		if(nextpack==0)memoryFilled=1;
	  }

	  
	  
	  if(len==sizeof(pack)){
		pack* myMsg=(pack*) payload;
		switch(myMsg->protocol){
			
			case FLOOD: //flooding distribute to whole network
			if(myMsg->dest!=TOS_NODE_ID){
				//dbg(GENERAL_CHANNEL, "Node %d is Forewarding packet meant for %d\n",TOS_NODE_ID,myMsg->dest);
				//dbg(GENERAL_CHANNEL, "PING EVENT \n");
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, FLOOD, myMsg->seq, (uint8_t*)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
				call Sender.send(sendPackage, AM_BROADCAST_ADDR);
			}else{
				dbg(GENERAL_CHANNEL, "Node %d recieved its packet: %s\n",TOS_NODE_ID,myMsg->payload);
			}break;
			
			case NEIGHBOR_PING: //neighbor discovery ping
				makePack(&sendPackage, TOS_NODE_ID, myMsg->src, myMsg->TTL, NEIGHBOR_REPLY, thisSeq++, (uint8_t*)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
				call Sender.send(sendPackage, myMsg->src);
			break;
			
			case NEIGHBOR_REPLY: //neighbor discovery reply
				if(!getNeighbor(globalNeighbors[TOS_NODE_ID], myMsg->src))numNeighbors++;
				setNeighbor(globalNeighbors[TOS_NODE_ID], myMsg->src);
				dbg(FLOODING_CHANNEL, "Adding %d to the neighbor list of %d\n",myMsg->src,TOS_NODE_ID);
			break;

			case LSP: //link state protocol decodes neighborlist
				//decode((uint8_t*)(myMsg->payload), globalNeighbors[(int)myMsg->src]);
				memcpy(globalNeighbors[(int)myMsg->src],(myMsg->payload),20);
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL, myMsg->protocol, myMsg->seq, (uint8_t*)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
				call Sender.send(sendPackage,AM_BROADCAST_ADDR);
				//dbg(ROUTING_CHANNEL, "Recieved list of %d neighbors from node  %d\n",countNeighbors(globalNeighbors[(int)myMsg->src]), myMsg->src);
				dj(globalNeighbors);
			break;

			case ROUTED: //lookup entry by destination & set dest next hop value
			if(myMsg->dest!=TOS_NODE_ID){
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL, myMsg->protocol, myMsg->seq, (uint8_t*)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
				dbg(ROUTING_CHANNEL, "Routing packet meant for %d via %d\n",myMsg->dest,routingTable[myMsg->dest].nextHop);
				call Sender.send(sendPackage,routingTable[myMsg->dest].nextHop);
			}else{
				dbg(GENERAL_CHANNEL, "Node %d recieved its packet: %s\n",TOS_NODE_ID,myMsg->payload);
			}
			break;
			
			case TCP:
			if(myMsg->dest!=TOS_NODE_ID){
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL, myMsg->protocol, myMsg->seq, (uint8_t*)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
				dbg(ROUTING_CHANNEL, "Routing packet meant for %d via %d\n",myMsg->dest,routingTable[myMsg->dest].nextHop);
				call Sender.send(sendPackage,routingTable[myMsg->dest].nextHop);
			}else{
				recvtcp = (tcpP*)myMsg->payload;
				dbg(GENERAL_CHANNEL, "Node %d recieved its tcp packet, delivering to layer: %s\n",TOS_NODE_ID,recvtcp->payload);
				call Transport.read(recvtcp->dest,recvtcp,PACKET_MAX_PAYLOAD_SIZE);
			}
			break;
			
		
		}
		return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      tcpP pak={0};
	  pak.dest=80;
	  memcpy(pak.payload,payload,sizeof(pak.payload));
	  dbg(GENERAL_CHANNEL, "PING EVENT \n");
	  dbg(FLOODING_CHANNEL, "Sending packet from node %d to %d \n",TOS_NODE_ID,destination);
      makePack(&sendPackage, TOS_NODE_ID, destination, TIME_TO_LIVE, TCP, thisSeq++, &pak, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, routingTable[destination].nextHop);
   }
   

   event void CommandHandler.printNeighbors(){
	   dbg(GENERAL_CHANNEL, "PING EVENT!!!!!!!!!\n");
   }

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){
	   setTestServer(80);
	   dbg(GENERAL_CHANNEL, "CALLED TEST SERVER \n");
   }

   event void CommandHandler.setTestClient(){
	   setTestClient(9, 8080, 80, 5);
	   dbg(GENERAL_CHANNEL, "CALLED TEST CLIENT \n");
   }

/**
//server
    event void SP_Timer.fired(){
//deals with connection and matching sockets
    }
//server
event void CP_Timer.fired(){
//deals with verifying mesg and write offs

}
**/

   event void CommandHandler.setAppServer(){
/**
    bool active =TRUE; //check connection active
    bool write_off= FALSE; //checks write stuff
    uint8_t write_counter; //check for mesg write stuff
    uint8_t i =0;
    if(payload[0] =='h' || payload=='H'){ //h hello
        SetPayload(payload); //make this function?
        signal CommandHandler.setTestClient(); //or call reg setTest
        active = TRUE;
        write_off=FALSE;
    }
    if(active == TRUE && call QueueC.size() >= 1){ //put users in a client Q
        if(payload[0] =='e' || payload[0]='E'){ //e hello
            SetPayload(payload); //set this thing again
            while(payload[i] != '\n'){ //check format
                i++;
            }
            write_counter =0;
            memcpy(tempbuff, getPayload(), (i+1)=sizeof(getPayload())); //copy
            write_off=FALSE;
            call CP_Timer.startPeriodic(some timer); //client timer?
            }
        if(payload[0] =='l' || payload[0]='L'){
            SetPayload(payload);
            while(payload[i] != '\n'){
            i++;
        }
        write_counter =0;
        memcpy(tempbuff, getPayload(), (i+1)=sizeof(getPayload()));
        write_off=FALSE;
        call CP_Timer.startPeriodic(some timer);//need to implement
        }
    }
**/
}

   event void CommandHandler.setAppClient(){
/**
        char chars[256]; //for le username
        int16_t count = 0; //char count
        uint8_t i =0;
        socket_addr_t address;
        socket_addr_t serverAddress;
        bool charFound = FALSE; //match default false
        fd = call Transport.socket();
        address.addr = TOS_NODE_ID; //curr node
        address.port = client;
        serverAddress.addr = 1; //node id
        serverAddress.port = 41; //listen port
        while (!charFound) {
            if (username[i] == '\n') { //look for the end
                chars[i] = username[i];//store
                count++;//char count
                charFound = TRUE;//it exists
            }
            else {
                chars[i] = username[i];
                count++;
                i++; //keep going
            }
        }
        printf("username length = %d\n", count);
        if (call Transport.bind(fd, &address) == SUCCESS) {
            //connect to other user with some function
        }
**/
    }

	event void periodicTimer.fired(){
		int i,c=0;
		uint8_t lspPayload[16385]={0}; //buffer payload
		char printBuf[spaceCalc()?spaceCalc():1];
		char* head = printBuf;
		if(refresh>=8&&numNeighbors){
			memset(printBuf,0,sizeof(printBuf));
			for(i=0;i<sizeof(globalNeighbors[TOS_NODE_ID])*8;i++){
				if(getNeighbor(globalNeighbors[TOS_NODE_ID], i)){
					head+=sprintf(head,"%d%c",i,(numNeighbors-(++c))?',':' ');
				}
			}
			dbg(NEIGHBOR_CHANNEL, "TIMER EVENT, sending out NEIGHBOR_PINGs,\nLast known neighbor list was: %s\n",printBuf);
			numNeighbors=0;
			
			memset(lspPayload,0,8192);
			//encode(lspPayload,globalNeighbors[TOS_NODE_ID]); //encodes neighbor list
			memcpy(lspPayload,globalNeighbors[TOS_NODE_ID],20);
			//dbg(GENERAL_CHANNEL, "sending %d neighbors list\n",countNeighbors(globalNeighbors[TOS_NODE_ID]));
			makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, TIME_TO_LIVE, LSP, thisSeq++, lspPayload, PACKET_MAX_PAYLOAD_SIZE); //sends LSP packets to whole network

			call Sender.send(sendPackage, AM_BROADCAST_ADDR); 

			refresh=0;
			if(countNodes(globalNeighbors)>1){
				//dbg(GENERAL_CHANNEL, "Runnind dij on node %d with %d totalnodes\n",TOS_NODE_ID,countNodes(globalNeighbors));
				//dbg(GENERAL_CHANNEL, "node %d has %d neighbors of a global %d\n",TOS_NODE_ID,countNeighbors(globalNeighbors[TOS_NODE_ID]),countNodes(globalNeighbors[TOS_NODE_ID]));
				dj(globalNeighbors);
				}
			//memset(globalNeighbors[TOS_NODE_ID],0,8192); //refresh
		}
		makePack(&sendPackage, TOS_NODE_ID, TOS_NODE_ID, 1, NEIGHBOR_PING, thisSeq++, "Looking for neighbors", PACKET_MAX_PAYLOAD_SIZE);
		call Sender.send(sendPackage, AM_BROADCAST_ADDR);
		refresh++;
		return;
	}
	
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }


	void setTestServer(uint16_t port){
		socket_addr_t address;
		socket_t fd = call Transport.socket();
		address.addr = TOS_NODE_ID;
		address.port = port;
		if (call Transport.bind(fd, &address) == SUCCESS) {
			dbg(TRANSPORT_CHANNEL, " this works\n");
		}
		if (call Transport.listen(fd) == SUCCESS) {
			dbg(TRANSPORT_CHANNEL, "listening\n");
		}
	
		dbg(TRANSPORT_CHANNEL, "Node %d set as server with port %d\n", TOS_NODE_ID, port);
		dbg(TRANSPORT_CHANNEL, "fd is %d\n", fd);
   }

   void setTestClient(uint16_t dest, uint16_t srcPort, uint16_t destPort, uint16_t transfer){
		pack syn;
		socket_addr_t address;
		socket_addr_t serverAddress;
		socket_t fd = call Transport.socket();
		address.addr = TOS_NODE_ID;
		address.port = srcPort;
		serverAddress.addr = dest;
		serverAddress.port = destPort;
		if (call Transport.bind(fd, &address) == SUCCESS) {
			dbg(TRANSPORT_CHANNEL, "client side works\n");
		}
		//send SYN packet
		call Transport.connect(fd, &serverAddress); 

		dbg(TRANSPORT_CHANNEL, "Node %d set as client with src port %d, and dest %d at their port %d\n", TOS_NODE_ID, srcPort, dest, destPort);
   }
}
