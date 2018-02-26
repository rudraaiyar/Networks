#ifndef __SOCKET_H__
#define __SOCKET_H__

#define DATA_FLAG 0
#define DATA_ACK_FLAG 1
#define SYN_FLAG 2
#define SYN_ACK_FLAG 3
#define ACK_FLAG 4
#define FIN_FLAG 5
#define ACK_FIN_FLAG 6
#define SATISFIED_FLAG 7

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
};

enum socket_state{
    CLOSED,
    LISTEN,
    ESTABLISHED,
    SYN_SENT,
    SYN_RCVD,
};

   enum {
   		//protocol numbers so that flooding is included
		FLOOD,
		NEIGHBOR_PING,
		NEIGHBOR_REPLY,
		LSP,
		ROUTED,
		TCP
   };

typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint16_t addr;
}socket_addr_t;


// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket. 
typedef struct socket_store_t{
    uint8_t flag;
    enum socket_state state;
    socket_addr_t src;
    socket_addr_t dest;

    // This is the sender portion.
    uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastWritten;
    uint8_t lastAck;
    uint8_t lastSent;

    // This is the receiver portion
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastRead;
    uint8_t lastRcvd;
    uint8_t nextExpected;

    uint16_t RTT;
    uint8_t effectiveWindow;
}socket_store_t;

	enum{
		TCP_PACKET_HEADER_LENGTH = 12,
		TCP_PACKET_MAX_PAYLOAD_SIZE = PACKET_MAX_PAYLOAD_SIZE - TCP_PACKET_HEADER_LENGTH
	};

	typedef struct tcpP{ //packet thats being passed around
		uint16_t dest;
		uint16_t src;
		uint8_t seq;
		uint8_t ack;
		uint8_t flags;
		uint8_t advertised_window;
		uint32_t timeStamp;
		uint8_t payload[TCP_PACKET_MAX_PAYLOAD_SIZE];
	}tcpP;

#endif