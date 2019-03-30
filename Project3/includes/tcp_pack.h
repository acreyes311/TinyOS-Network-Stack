#ifndef TCP_PACKET_H
#define TCP_PACKET_H

#include "protocol.h"
#include "channels.h"

#define SYN_FLAG		1
#define SYN_ACK_FLAG	2
#define ACK_FLAG 		3

#define TCP_MAX_PAYLOAD_SIZE 11

typedef nx_struct tcp_pack{
	nx_uint8_t destPort;
	nx_uint8_t srcPort;
	nx_uint8_t seq;	//16?
	nx_uint8_t ACK;	//16?
	nx_uint8_t lastACK;
	nx_uint8_t flag;
	nx_uint8_t window;
	nx_uint8_t payload[TCP_MAX_PAYLOAD_SIZE];

}tcp_pack;

#endif