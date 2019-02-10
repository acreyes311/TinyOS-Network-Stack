/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */



/*
 * TODO: 
 * Segmentation Error line 290
 * Fix all the If statements to correct order
 * Try to restructure more stuff *_* 
*/

#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"


typedef nx_struct Neighbor {
   nx_uint16_t nodeID;
   nx_uint16_t hops;
}Neighbor;

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   //Added Modules
   uses interface Timer<TMilli> as periodicTimer;  // Interface wired in NodeC.nc
   uses interface Random as Random; //used to avoid timer interruption/congestion

   // Will need List of packets and Neighbors 
   uses interface List<pack> as Packets;  // List of Packets
   uses interface List<Neighbor > as Neighbors;   // List of Known Neighbors
   uses interface List<Neighbor > as DroppedNeighbors;  // List of Neighbors dropped out of network
}




implementation{
   pack sendPackage;
   uint16_t seqNumber = 0; 
   Neighbor NewNeighbor;
   Neighbor TempNeighbor;

   // Prototypes

   bool isKnown(pack *p);  // already seen function
   void insertPack(pack p); // push into list
   void neighborList(); // neighbor list
   
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   // insertPack checks to see if list is full if not insert pack at back of list
   
   void insertPack(pack p) {
      if (call Packets.isFull()) {
         call Packets.popfront();
      }
      else {
         call Packets.pushback(p);  // insert at back of list
      }
   }

   event void Boot.booted(){
       //uint32_t start;
      // uint32_t end;
      call AMControl.start();  
     
      dbg(GENERAL_CHANNEL, "Booted\n");

     //start = call Random.rand32() % 2000;   // random up to 2000 ms
     //end = call Random.rand32() % 10000 + 2000;  // 10000-12000 ms
      // Call to timer fired event
      //dbg(GENERAL_CHANNEL, "BEFORE START TIMER\n");
      //call periodicTimer.startPeriodicAt(start,end); //starts timer // from start to end
      // Or just
     //call periodicTimer.startPeriodic(1000); //1000 ms
     //dbg(NEIGHBOR_CHANNEL, "START TIMER at %d, end at %d\n",start,end);
   }

   void neighborList() {
   	//pack package;
   	char *msg;
   	uint16_t size;
   	uint16_t i = 0;
   	//uint16_t hops;
   	Neighbor line;
   	Neighbor temp;
    size = call Neighbors.size();

   	//dbg(NEIGHBOR_CHANNEL, "NeighborList, node %d looking for neighbor\n",TOS_NODE_ID);
   	if(!call Neighbors.isEmpty()) {
   		dbg(NEIGHBOR_CHANNEL, "NeighborList, node %d looking for neighbor\n",TOS_NODE_ID);
   		// Loop through Neighbors List and increase hops
   		for (i = 0; i < size; i++) {
   			line = call Neighbors.get(i);
   			//temp.hops = temp.hops + 1;
        line.hops++;
        call Neighbors.remove(i);
        call Neighbors.pushback(line);
   		}
   		for (i = 0; i < size; i++) {
   			temp = call Neighbors.get(i);
   			//hops = temp.hops;

   			// Drop expired neighbors after 3 pings and put in DroppedList
   			if (temp.hops > 3) {
   				//line = call Neighbors.remove(i);
          call Neighbors.remove(i);
   				dbg(NEIGHBOR_CHANNEL,"Node %d has EXPIRED and DROPPED from Node %d\n",line.nodeID,TOS_NODE_ID);
   				//call DroppedNeighbors.pushfront(line);
   				i--;
   				size--;
   			}
   		}
   	}
   	// Ping list of neighbors
   	msg = "Message\n";
   	makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR,2,PROTOCOL_PING,1,(uint8_t*)msg,(uint8_t)sizeof(msg));
   	insertPack(sendPackage);
   	call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }

   //PeriodicTimer Event implementation
   event void periodicTimer.fired() {
        // neighbor discovery function call or implement discovery here
       // dbg(GENERAL_CHANNEL, "Call to neighborList()\n");
        neighborList();
        
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         call periodicTimer.startPeriodic(1000); //1000 ms
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
   {
      bool flag;
      uint16_t size;
      uint16_t i = 0;

      
      if(len==sizeof(pack))
      {

         pack* myMsg=(pack*) payload;  // Message of received package
                  
         //dbg(GENERAL_CHANNEL, "Package  received from : %d\n", myMsg->src);
         //dbg(FLOODING_CHANNEL,"Packet being flooded to %d\n", myMsg->dest);

         
         if(myMsg->TTL == 0) {
         // Drop packet if expired or seen
            dbg(FLOODING_CHANNEL,"TTL = 0, PACKET #%d from %d to %d being dropped\n", myMsg->seq, myMsg->src, myMsg->dest);
         }
         if(isKnown(myMsg)) {
            dbg(FLOODING_CHANNEL,"Already seen PACKET #%d from %d to %d being dropped\n", myMsg->seq, myMsg->src, myMsg->dest);
         }
       if(AM_BROADCAST_ADDR == myMsg->dest) {            

            // What protocol does the message contain
          // switch(myMsg->protocol) {
              
                //PROTOCOL_PING SWITCH CASE
               //case PROTOCOL_PING:
               if(myMsg->protocol == PROTOCOL_PING){
                  dbg(GENERAL_CHANNEL, "myMsg->Protocol %d\n", myMsg->protocol);
                  //Look for neighbors
                  dbg(NEIGHBOR_CHANNEL, "Packet from %d searching for neighbors\n",myMsg->src);
                  //makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, (uint8_t *) myMsg->payload, sizeof(myMsg->payload));
                  makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                  insertPack(sendPackage); // Insert pack into our list
                  call Sender.send(sendPackage, myMsg->src);
                 // break;
               }

              // case PROTOCOL_PINGREPLY:
               if(myMsg->protocol == PROTOCOL_PINGREPLY) {
                  dbg(NEIGHBOR_CHANNEL, "Received a Ping Reply from %d\n", myMsg->src);
                  size = call Neighbors.size(); // get size from our List of Neighbors
                  flag = FALSE;  // Initiate to FALSE in declaration?? Set to true only when neighbor is found

                  // loop through our list of Neighbors and see if match is found
                  // CAN TRY A WHILE LOOP ??
                  for(i = 0; i < size; i++){
                     TempNeighbor = call Neighbors.get(i);
                     // CHECK FOR A MATCH, IF TRUE RESET HOPS( NEW NAME ?)
                     if(TempNeighbor.nodeID == myMsg->src){
                        dbg(NEIGHBOR_CHANNEL, "Node %d found in Neighbors List\n", myMsg->src);
                        TempNeighbor.hops = 0;
                        flag = TRUE;
                      //  break;
                     }
                  }
                 // break;
               }
                  // If neighbor is not found in our list then it is New and need to add it to the list
                  if(!flag) {
                    // uint16_t temp;
                     dbg(NEIGHBOR_CHANNEL, "New Neighbor %d found and adding to our list\n", myMsg->src);
                     

                     if(call DroppedNeighbors.isEmpty()){
                     
                     NewNeighbor = call DroppedNeighbors.popfront();
                     dbg(GENERAL_CHANNEL, "1st !\n");
                     //NewNeighbor = call DroppedNeighbors.get();
                     //temp = myMsg->src;
                     NewNeighbor.nodeID =  myMsg->src;
                    // NewNeighbor->nodeID = temp;
                     dbg(GENERAL_CHANNEL, "2nd !!\n");
                     NewNeighbor.hops = 0;
                     dbg(GENERAL_CHANNEL, "3rd !!\n");
                     call Neighbors.pushback(NewNeighbor);
                     dbg(GENERAL_CHANNEL, "pushback New Neighbor\n");
                 }
                 else{
                  NewNeighbor = call DroppedNeighbors.popfront();
                  NewNeighbor.nodeID = myMsg->src;
                  NewNeighbor.hops = 0;
                  call Neighbors.pushback(NewNeighbor);
                 }
                }
                 // break;
                // Default switch case; Break  
              // default:
                 // break;                   
            }
         if(myMsg->dest == TOS_NODE_ID) 
         {
            dbg(FLOODING_CHANNEL,"Packet #%d arrived from %d with payload: %s\n", myMsg->seq, myMsg->src, myMsg->payload);
            // dont push PROTOCOL_CMD into list, will not allow same node to send multiple pings

           // if(myMsg->protocol != PROTOCOL_CMD) {
             //  insertPack(*myMsg); // push non protol_cmd into packet list
          //  }

            /////BEGIN CHECKING FLOODING PROTOCOLS////

            // PROTOCOL_PING: packet was pinged but no reply
            if(myMsg->protocol == PROTOCOL_PING) {
               dbg(FLOODING_CHANNEL,"Ping replying to %d\n", myMsg->src);
               //makepack with myMsg->src as destination
               // Two ways.
               //makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, sendPackage.seq+1,(uint8_t *)myMsg->payload, sizeof(myMsg->payload));               
               makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, seqNumber, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
               seqNumber++;   // increase sequence id number
               // Push into seen/sent package list
               insertPack(sendPackage);
               // Send new packet
               call Sender.send(sendPackage, AM_BROADCAST_ADDR);               
            }

            // PROTOCOL PINGREPLY: Packet at correct destination; Stop sending packet
            if(myMsg->protocol == PROTOCOL_PINGREPLY) {
               dbg(FLOODING_CHANNEL, "PING REPLY RECEIVED FROM %d\n ",myMsg->src);
            }

            //////////////////////  MAY BE IN WRONG SPOT  MIGHT NEED TO BE MOVED BELOW IF(BROADCAST ADDRESS) /////////////////////
            // ELSE packet does not belong to current node, flood packet
            /*
            else {
              // makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
               makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
               //makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
               dbg(FLOODING_CHANNEL, "Packet from %d, intended for %d is being Rebroadcasted./n", myMsg->src, myMsg->dest);
               insertPack(sendPackage);   // Packet to be inserted into seen packet list

               call Sender.send(sendPackage, AM_BROADCAST_ADDR);  // Resend packet
            }  
            */
         }
         else {
              // makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
               makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
               //makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
               dbg(FLOODING_CHANNEL, "Packet from %d, intended for %d is being Rebroadcasted./n", myMsg->src, myMsg->dest);
               insertPack(sendPackage);   // Packet to be inserted into seen packet list

               call Sender.send(sendPackage, AM_BROADCAST_ADDR);  // Resend packet
            } 
         // Neighbor Discovery
         // Packets receive a packet from broadcast address
         // Check to see if packet searching for neighbors
     
        
        //}
           // End if(AMBROADCAST)
         // Packet does not belong to current node         
     /*    else {
              // makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
               makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
               //makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
               dbg(FLOODING_CHANNEL, "Packet from %d, intended for %d is being Rebroadcasted./n", myMsg->src, myMsg->dest);
               insertPack(sendPackage);   // Packet to be inserted into seen packet list
               call Sender.send(sendPackage, AM_BROADCAST_ADDR);  // Resend packet
            }  
         */
         ///////////////////

         //dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         return msg;
      }
      
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;

   }



   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      sendPackage.seq = sendPackage.seq + 1;
      makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, sendPackage.seq, payload, PACKET_MAX_PAYLOAD_SIZE);
      //makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, seqNumber, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR); 
      //seqNumber = seqNumber + 1;
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
   bool isKnown(pack *p) {
         uint16_t size = call Packets.size(); // size of our packet list
         pack temp;
         uint16_t i =0;
         for(i = 0; i < size; i++) {
            temp = call Packets.get(i);   // set temp to indexed packet in packet list
            // Checks for same source destination and sequence #
            if ((temp.src == p->src) && (temp.dest == p->dest) && (temp.seq == p->seq)){
               return TRUE;
             }
         }
         return FALSE;     
      }
}
