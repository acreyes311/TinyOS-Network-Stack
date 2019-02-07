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

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   //Added Modules
   uses interface Timer<TMilli> as periodicTimer;	// Interface wired in NodeC.nc
   uses interface Random as Random;	//used to avoid timer interruption/congestion

   // Will need List of packets and Neighbors 
   uses interface List<pack> as Packets;
   uses interface List<Neighbor *> as Neighbors;
}

// Neighbor struct for node ID and number of hops/ping
typedef nx_struct Neighbor{
   nx_uint16_t nodeID;
   nx_uint16_t hops;
}Neighbor;

implementation{
   pack sendPackage;
   uint16_t seqNumber = 0; 

   // Prototypes

   bool isKnown(pack *P);	// already seen function
   void insertPack(pack p); // push into list
   void neighborList(); // neighbor list

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   // insertPack checks to see if list is full if not insert pack at back of list
   // implement isFull in dataStructures/interfaces List.nc/ListC.nc
   void insertPack(pack p) {
      if (call Packets.isFull()) {
         call Packets.popfront();
      }
      else {
         call Packets.pushback(p);  // insert at back of list
      }
   }

   event void Boot.booted(){
   	  uint32_t start;
   	  uint32_t end;
      call AMControl.start();  
     
      dbg(GENERAL_CHANNEL, "Booted\n");

      start = call Random.rand32() % 2000;	// random up to 2000 ms
      end = call Random.rand32() % 10000 + 2000;  // 10000-12000 ms

      // Call to timer fired event
      call periodicTimer.startPeriodic(start,end);	//starts timer
      // Or just
     // call periodicTimer.startPeriodic(1000); //1000 ms
     dbg(NEIGHBOR_CHANNEL, "START TIMER");
   }

   //PeriodicTimer Event implementation
   event void periodicTimer.fired {
   	  // neighbor discovery function call or implement discovery here
        dbg(NEIGHBOR_CHANNEL, "Call to neighborList()");
        neighborList();
        
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
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;	// Message of received package
         dbg(GENERAL_CHANNEL, "Package  received from : %s\n", myMsg->src);
         dbg(FLOODING_CHANNEL,"Packet being flooded to %d\n", myMsg->dest);

         ///////////////////
         //if((myMsg->TTL == 0 || isKnown(myMsg)){	// call to isKnown();  Can seperate into 2 if else statements
         if(myMsg->TTL == 0) {
         // Drop packet if expired or seen
            dbg(FLOODING_CHANNEL,"TTL = 0, PACKET #%d from %d to %d being dropped\n", myMsg->seq, myMsg->src, myMsg->dest);
         }
         if(myMsg->isKnown(myMsg)) {
            dbg(FLOODING_CHANNEL,"Already seen PACKET #%d from %d to %d being dropped\n", myMsg->seq, myMsg->src, myMsg->dest);
         }

         
         if(myMsg->dest == TOS_NODE_ID) {
            dbg(FLOODING_CHANNEL,"Packet #%d arrived from %d with payload: %s\n", myMsg->seq, myMsg->src, myMsg->payload);
            // dont push PROTOCOL_CMD into list, will not allow same node to send multiple pings

            if(myMsg->protocol != PROTOCOL_CMD) {
               pushPack(*myMsg); // push non protol_cmd into packet list
            }

            /////BEGIN CHECKING PROTOCOLS////

            // PROTOCOL_PING: packet was pinged but no reply
            if(myMsg->protocol == PROTOCOL_PING) {
               dbg(FLOODING_CHANNEL,"Ping replying to %d\n", myMsg->src);
               //makepack with myMsg->src as destination
               // Two ways.
               makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, sendPackage.seq+1,(uint8_t *)myMsg->payload, sizeof(myMsg->payload));               
               //makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, seqNumber, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
               seqNumber++;   // increase sequence id number
               // Push into seen/sent package list
               pushPack(sendPackage);
               // Send new packet
               call Sender.send(sendPackage, AM_BROADCAST_ADDR);               
            }

            // PROTOCOL PINGREPLY: Packet at correct destination; Stop sending packet
            else if(myMsg->protocol == PROTOCOL_PINGREPLY) {
               dbg(FLOODING_CHANNEL, "PING REPLY RECEIVED FROM %d\n ",myMsg->src);
            }
            // ELSE packet does not belong to current node, flood packet
            else {
              // makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
               makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
               dbg(FLOODING_CHANNEL, "Packet from %d, intended for %d is being Rebroadcasted./n", myMsg->src, myMsg->dest);
               insertPack(sendPackage);   // Packet to be inserted into seen packet list

               call Sender.send(sendPackage, AM_BROADCAST_ADDR);  // Resend packet
            }	

         }
         // Packets receive a packet from broadcast address
         // Check to see if packet searching for neighbors
         if(AM_BROADCAST_ADDR == myMsg->dest) {
            
         }

         ///////////////////

         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }



   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      sendPackage.seq = sendPackage.seq + 1;
      makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR); 
      //destination);
   }

   event void CommandHandler.printNeighbors(){}

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

   /*
   	isKnown bool function check to see if packet is in list of sent/received(seen) packets
   */
   bool isKnown(pack *P) {
   		uint16_t size = call Packets.size(); // size of our packet list
   		pack temp;

   		for(int i = 0; i < size; i++) {
   			temp = call Packets.get(i);	// set temp to indexed packet in packet list
   			// Checks for same source destination and sequence #
   			if ((temp.src == P->src) && (temp.dest == P->dest) && (temp.seq == P->seq))
   				return TRUE;
   		}
   		return FALSE;		
   	}
   }
}