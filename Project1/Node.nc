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
   use interface List<pack> as Packets;
}

implementation{
   pack sendPackage;

   // Prototypes

   bool isKnown(pack *P);	// already seen function


   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);


   event void Boot.booted(){
   	  uint32_t start;
   	  uint32_t end;
      call AMControl.start();  
     
      dbg(GENERAL_CHANNEL, "Booted\n");

      start = call Random.rand32() % 2000;	// random up to 2000 ms
      end = call Random.rand32() % 10000 + 2000;  // 10000-12000 ms

      // Call to timer fired event
      call periodicTimer.startPeriodic(start,end);	//starts timer
   }

   //PeriodicTimer Event implementation
   event void periodicTimer.fired {
   	  // neighbor discovery function call or implement discovery here

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
         ///////////////////
         if((myMsg->TTL == 0 || isKnown(myMsg)){	// call to isKnown()
         // Do nothing if expired or seen

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
