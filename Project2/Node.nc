
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

/*  TODO
 * - Figure out how to use LinkState struct
 *      - Maybe once inside receive protocol_linkstate we can see what we need?
 * - Finish makeLSP
 * - Follow makeLSP packet to receive-> PROTOCOL = LINKSTATE
 *       - Figure out what to do inside protocol
 * - Dijkstra T_T
 * - Figure out Route Table
 * - Do we need to check/update neighbors?
 * - Calculate cost: The difference in TTL's?
 *      - It took MaxTTL-MyTTL to get here ?
 * - Might have to change from switch case to IF/ELSE, getting too many weird errors
 * - FINAL RouteTable print confirmed list, destination, cost, nextHop
*/


typedef nx_struct Neighbor {
   nx_uint16_t nodeID;
   nx_uint16_t life;
}Neighbor;

/* 
 * LinkState struct contains:
 * - ID of node that created
 * - List of directly connected neighbors
 * - A sequence number 
 * - Cost
 * - Next
 */
typedef nx_struct LinkState {
    nx_uint16_t neighbors[64]; // current list of neighbors
    nx_uint16_t arrLength;
    nx_uint16_t node; // Dest?
    nx_uint16_t cost; 
    nx_uint16_t seq;
    nx_uint16_t nextHop;
    }LinkState;



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
   // ----- Project2 -----
   // Two lists mentioned in book
   uses interface List<LinkState> as Tentative;
   uses interface List<LinkState> as Confirmed;
   uses interface List<LinkState> as RouteTable;
   uses interface List<LinkState> as routeTemp;
   uses interface List<LinkState> as tempLS;
   // New Timer for LSP 
   uses interface Timer<TMilli> as lspTimer; // fires and call function to create LSP packet

}


implementation{
   pack sendPackage;
   uint16_t seqNumber = 0; 
   uint16_t lspCount = 0;
   Neighbor NewNeighbor;
   Neighbor TempNeighbor;

   // Prototypes

   bool isKnown(pack *p);  // already seen function
   void insertPack(pack p); // push into list
   void neighborList(); // neighbor list

   // ---------Project 2 ------------//
   void makeLSP();
   void dijkstra();
   void printLSP();
   
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
      // uint32_t start;
      // uint32_t end;
      call AMControl.start();  
     
      dbg(GENERAL_CHANNEL, "Booted\n");

   }

   /*
    * neighborList() function Loops through our neighbor list if not empty
    * and increase the life/pings/life of each neighbor (number of pings since they were last heard)
    * Check list again for any Neighbor with life > 3 and drop them as expired. Add to Drop list
    * Repackage ping with AM_BROADCASE_ADDR as destination   
   */
   void neighborList() {
    //pack package;
    char *msg;
    uint16_t size;
    uint16_t i = 0;
    
    Neighbor line;
    Neighbor temp;
    size = call Neighbors.size();
    lspCount++;
    // Trouble with Neighbor* we need to call function get to retrieve each neighbor
    // ..Cant change life directly (!neighbor->life)

    //Check to see if neighbors have been found
    if(!call Neighbors.isEmpty()) {
 //     dbg(NEIGHBOR_CHANNEL, "NeighborList, node %d looking for neighbor\n",TOS_NODE_ID);
      // Loop through Neighbors List and increase life/pings/age if not seen
      //  will be dropped every 5 pings a neighbor is not seen.
      for (i = 0; i < size; i++) {
        line = call Neighbors.get(i);
        line.life++;
        call Neighbors.remove(i);
        call Neighbors.pushback(line);
      }
      for (i = 0; i < size; i++) {
        temp = call Neighbors.get(i);
        //life = temp.life;

        // Drop expired neighbors after 3 pings and put in DroppedList
        if (temp.life > 5) {
          //line = call Neighbors.remove(i);
          call Neighbors.remove(i);
          //dbg(NEIGHBOR_CHANNEL,"Neighbor %d has EXPIRED and DROPPED from Node %d\n",line.nodeID,TOS_NODE_ID);
          call DroppedNeighbors.pushfront(line);
          i--;
          size--;
        }
      }
    }
 //   signal CommandHandler.printNeighbors();
    // After Dropping expired neighbors now Ping list of neighbors
    msg = "Message\n";
    // Send discovered packets, destination AM_BROADCAST
    makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR,2,PROTOCOL_PING,1,(uint8_t*)msg,(uint8_t)sizeof(msg));
    insertPack(sendPackage);
    call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }

   //PeriodicTimer Event implementation
   event void periodicTimer.fired() {
        // dbg(GENERAL_CHANNEL, "Call to neighborList()\n");
        neighborList();
        if(lspCount > 1 && lspCount % 3 == 0 && lspCount < 16){
          makeLSP();
        }
        //makeLSP(); 
        if(lspCount > 1 && lspCount % 20 == 0 && lspCount < 61){}
          dijkstra();        

        /*
        if(lspCount < 17 && lspCount %3 == 2 && lspCount > 1){
          makeLSP();
        }

        if(lspCount == 17)
          dijkstra();
        */           
   }


   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         // Call timer to fire at intervals between 
         //call periodicTimer.startPeriodicAt(1,1000); //1000 ms
         call periodicTimer.startPeriodic(1000);
         //call lspTimer.startPeriodic(100);
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
      LinkState LSP;
      LinkState temp;
      Neighbor lspNeighbor;
      uint16_t lsSize = 0;  // link state-> arrLength
      bool match;


      if(len==sizeof(pack))
      {

         pack* myMsg=(pack*) payload;  // Message of received package
                  
         //dbg(GENERAL_CHANNEL, "Package  received from : %d\n", myMsg->src);
         //dbg(FLOODING_CHANNEL,"Packet being flooded to %d\n", myMsg->dest);
         
         if(myMsg->TTL == 0) {
         // Drop packet if expired or seen 
         }
         if(isKnown(myMsg)) {
   //         dbg(FLOODING_CHANNEL,"Already seen PACKET #%d from %d to %d being dropped\n", myMsg->seq, myMsg->src, myMsg->dest);
         }
         
         // Neighbor Discovery or LSP entry
       else if(AM_BROADCAST_ADDR == myMsg->dest) {            
   //       dbg(NEIGHBOR_CHANNEL, "Received a Ping Reply from %d\n", myMsg->src);
            // What protocol does the message contain
           switch(myMsg->protocol) {

                //PROTOCOL_PING SWITCH CASE //
                // repackage with TTL-1 and PING_REPLY PROTOCOL
               case PROTOCOL_PING:
                  //dbg(GENERAL_CHANNEL, "myMsg->Protocol %d\n", myMsg->protocol);                  
                 // dbg(NEIGHBOR_CHANNEL, "Packet from %d searching for neighbors\n",myMsg->src);
                 // makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, (uint8_t *) myMsg->payload, sizeof(myMsg->payload));
                  makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                  insertPack(sendPackage); // Insert pack into our list
                  call Sender.send(sendPackage, myMsg->src);  // Send with pingreply protocol
                  break;
               
              // PROTOCOL_PINGREPLY SWITCH CASE //
               
                case PROTOCOL_PINGREPLY:                  
                 
                  size = call Neighbors.size(); // get size from our List of Neighbors
                  flag = FALSE;  //  Set to true only when neighbor is found

                  // loop through our list of Neighbors and see if match is found
                  for(i = 0; i < size; i++){
                     TempNeighbor = call Neighbors.get(i);
                     // CHECK FOR A MATCH, IF TRUE RESET life
                     if(TempNeighbor.nodeID == myMsg->src){
                        //dbg(NEIGHBOR_CHANNEL, "Node %d found in Neighbors List\n", myMsg->src);
                       
                        TempNeighbor.life = 0;
                        flag = TRUE;
                        //break;
                     }
                     //dbg(NEIGHBOR_CHANNEL, "Received a Ping Reply from %d\n", myMsg->src);
                  }
                  //break;                
               
                  // If neighbor is not found in our list then it is New and need to add it to the list
                  if(!flag) { // No Match                   
         //            dbg(NEIGHBOR_CHANNEL, "New Neighbor %d found and adding to our list\n", myMsg->src);
                     
                     if(call DroppedNeighbors.isEmpty()){
                     
                     NewNeighbor = call DroppedNeighbors.popfront();  //Get new neighbor                   
                     NewNeighbor.nodeID =  myMsg->src;  // add src id                    
                     NewNeighbor.life = 0;  // reset life
                     call Neighbors.pushback(NewNeighbor);  // push into list
           //          dbg(GENERAL_CHANNEL, "pushback New Neighbor!\n");
                 }
                 else{
                  NewNeighbor = call DroppedNeighbors.popfront();
                  NewNeighbor.nodeID = myMsg->src;
                  NewNeighbor.life = 0;
                  call Neighbors.pushback(NewNeighbor);
                 }
                }

                  break;
            // ---------------- PROJECT 2 -------------------//
                // Go here After flooding LSP/ calculate route
                /*  Linkstate Protocol
                  Checks to see if LSP already has copy
                  If not Store LSP
                  If it does -> compare seq # and store larger seq #
                  If received LSP is newest, send that copy to all its neighbors and they do same
                  ->most recent LSP eventually reaches all nodes
                */
                case PROTOCOL_LINKSTATE:                             
                  //LinkState LSP;
                  //LinkState routeTemp;
                  //Neighbor lspNeighbor;
                  //uint16_t i;
                  //uint16_t lsSize;  // link state-> arrLength
                  //bool match;
                 // dbg(ROUTING_CHANNEL, "Node: %d successfully received an LSP Packet from Node %d! Cost: %d \n", TOS_NODE_ID, myMsg->src, MAX_TTL - myMsg->TTL);
                  //dbg(ROUTING_CHANNEL, "Payload Array length is: %d \n", call RouteTable.size());
                  match = FALSE;
                  //Check for LSP and current node match
                  // If node already has copy of LSP
                  if(myMsg->src == TOS_NODE_ID){
                    dbg(ROUTING_CHANNEL, "Match found. Dont Flood pack\n");
                    // set flag = true
                    match = TRUE;
                  }
                  // if our table IS empty; Initialize and push into our RouteTable
                  if(call RouteTable.isEmpty()){
                    temp.node = TOS_NODE_ID;
                    temp.nextHop = TOS_NODE_ID;
                    temp.seq = 0;
                    temp.arrLength = call Neighbors.size();
                    temp.cost = 0;
                    for(i = 0; i< temp.arrLength; i++) {
                      lspNeighbor = call Neighbors.get(i);
                      temp.neighbors[i] = lspNeighbor.nodeID;
                    }
                    call RouteTable.pushfront(temp);
                    //break;
                    dbg(GENERAL_CHANNEL,"RouteTable size: %d\n",call RouteTable.size());
                    dbg(GENERAL_CHANNEL,"msgTTL:%d, LSP cost:%d from:%d arrLen:%d\n", myMsg->TTL, LSP.cost, myMsg->src,LSP.arrLength);
                  }
                  // Else src is not current node 
                  
                  //else{
                  if(myMsg->src != TOS_NODE_ID){
                   // dbg(GENERAL_CHANNEL,"INSIDE IF(my->src != TOSNODE\n");
                    LSP.node = myMsg->src;
                    LSP.seq = myMsg->seq;
                    //LSP.nextHop = myMsg->src; // not tos_node
                    LSP.cost = MAX_TTL - myMsg->TTL; // Took this many life to get here
                    //dbg(GENERAL_CHANNEL,"msgTTL:%d, LSP cost:%d from:%d\n",myMsg->TTL, LSP.cost, myMsg->src);
                    i = 0;
                    lsSize = 0;
                    while(myMsg->payload[i] > 0){
                      //dbg(GENERAL_CHANNEL,"INSIDE while 1 !!)\n");
                      //Fill the LSP tables directly connected neighbors
                      LSP.neighbors[i] = myMsg->payload[i];
                      lsSize++;
                      i++;
                    }
                    //LSP.nextHop = 0;
                    LSP.arrLength = lsSize;

                    if(!call RouteTable.isEmpty()){
                    //dbg(GENERAL_CHANNEL,"INSIDE IF(!RT emptY)\n");

                      while(!call RouteTable.isEmpty()) {
                         //dbg(GENERAL_CHANNEL,"INSIDE WHILE 2 !!!\n");
                        temp = call RouteTable.front();
                        //dbg(GENERAL_CHANNEL,"INSIDE WHILE 2 !!!\n");
                        // Check for most current LSP(cost)
                        if((LSP.node == temp.node)&&(LSP.cost <= temp.cost)){
                           //dbg(GENERAL_CHANNEL,"INSIDE IF COST CHECK\n");
                          call RouteTable.popfront();  // Remove older LSP 
                        }
                        else if((LSP.node == temp.node) && (LSP.cost > temp.cost)){
                          call tempLS.pushfront(call RouteTable.front());
                          call RouteTable.popfront();
                        }
                        //dbg(GENERAL_CHANNEL,"INSIDE WHILE 2 !!!\n");
                        else {
                          //dbg(GENERAL_CHANNEL,"INSIDE ELSE CHECK \n");
                          call tempLS.pushfront(call RouteTable.front());
                          call RouteTable.popfront();
                        }
                      }
                        
                        while(!call tempLS.isEmpty()){
                          //dbg(GENERAL_CHANNEL,"INSIDE WHILE 2 !!!\n");
                          call RouteTable.pushfront(call tempLS.front());
                          call tempLS.popfront();
                        }
                      
                      /*
                      i = 0;
                      lsSize = 0;
                      while(myMsg->payload[i] > 0){
                        //Fill the LSP tables directly connected neighbors
                        LSP.neighbors[i] = myMsg->payload[i];
                        lsSize++;
                        i++;
                      }
                      */
                      
                      //LSP.arrLength = lsSize;
                      dbg(GENERAL_CHANNEL,"msgTTL:%d, LSP cost:%d from:%d arrLen:%d\n"
                        ,myMsg->TTL, LSP.cost, myMsg->src,LSP.arrLength);                      
                      call RouteTable.pushfront(LSP);
                      //printLSP();
                      seqNumber++;
                      makePack(&sendPackage, myMsg->src, AM_BROADCAST_ADDR, myMsg->TTL-1, PROTOCOL_LINKSTATE,
                        seqNumber, (uint8_t*)myMsg->payload, (uint8_t)sizeof(myMsg->payload));
                      insertPack(sendPackage);
                      call Sender.send(sendPackage,AM_BROADCAST_ADDR);

                    }
                    //If no match to protocol LINKSTATE
                  /*
                    -If no Match make; Make LSP table and flood it if node hasn't seen
                    -If no match between packet src and TOS_ID
                        ->then Unique nodeID for RouteTable
                        ->Store and replace with lowest cost
                  */
                    if(!match){                    

                    }


                  }
                  break;  // break Case LINKSTATE

                // Default switch case; Break  
              default:
                  break;                   
            }
          }
          // End Broadcast
         else if(myMsg->dest == TOS_NODE_ID) 
         {
            dbg(FLOODING_CHANNEL,"Packet #%d arrived from %d with payload: %s\n", myMsg->seq, myMsg->src, myMsg->payload);
            // dont push PROTOCOL_CMD into list, will not allow same node to send multiple pings

            if(myMsg->protocol != PROTOCOL_CMD) {
               insertPack(*myMsg); // push non protol_cmd into packet list
            }

            /////BEGIN CHECKING FLOODING PROTOCOLS////

            // PROTOCOL_PING: packet was pinged but no reply
            if(myMsg->protocol == PROTOCOL_PING) {
        //       dbg(FLOODING_CHANNEL,"Ping replying to %d\n", myMsg->src);
               //makepack with myMsg->src as destination
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
       //        dbg(FLOODING_CHANNEL, "PING REPLY RECEIVED FROM %d\n ",myMsg->src);
            }

         }
      
         // Packet does not belong to current node 
         // Flood Packet with TTL - 1
         else {
               makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
               //makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
        //       dbg(FLOODING_CHANNEL, "Packet from %d, intended for %d is being Rebroadcasted.\n", myMsg->src, myMsg->dest);
               insertPack(sendPackage);   // Packet to be inserted into seen packet list
               call Sender.send(sendPackage, AM_BROADCAST_ADDR);  // Resend packet
            }          

         //dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         return msg;
      }
      
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }



   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT____________________________________ \n");
      //sendPackage.seq = sendPackage.seq + 1;
      //makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, sendPackage.seq, payload, PACKET_MAX_PAYLOAD_SIZE);
      makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, seqNumber, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR); 
      seqNumber = seqNumber + 1;
      
   }

   event void CommandHandler.printNeighbors(){
    //go in your neighbor list
    //and print out that list
    //that list should be your neighbor ids.
    //neighborList(TOS_NODE_ID);
    //3 , 5
    Neighbor nextneightbor;
      uint16_t i=0;
      uint16_t size;
      size = call Neighbors.size(); 
      //dbg(NEIGHBOR_CHANNEL , "Neighbor Channel\n");
      if(size == 0){
        dbg(NEIGHBOR_CHANNEL, "-There is no Neighbor to node: %d\n", TOS_NODE_ID);
      }
      else
      {
        for(i =0; i < size; i++){
            nextneightbor=  call Neighbors.get(i);
            dbg(NEIGHBOR_CHANNEL, "<--- Has Neighbor: %d\n", nextneightbor.nodeID);
          }
      }
}



   event void CommandHandler.printRouteTable(){
      LinkState routing;
      uint16_t i =0;
      //uint16_t size;
      //size = call Confirmed.size();
      dbg(ROUTING_CHANNEL, "ROUTING Channel\n");
      for(i =0; i < call Confirmed.size(); i++){
            routing=  call Confirmed.get(i);
            dbg(ROUTING_CHANNEL, "--The Destination is %d\n  | The Cost is : %d\n  |  The next rout is %d\n", routing.node, routing.cost, routing.nextHop); //add i 
      }
   }

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

   //Link State Pack Timer
   event void lspTimer.fired() {        
     //makeLSP();        
   }   
   /* makeLSP()
    *  Check Neighbor List
    *  Make array of neighbors or cost ?
    *  Make pack, broadcast, linkstate protocol, array payload
   */
   void makeLSP(){
      pack LSP;
      //Neighbor temp;
      //uint16_t size = (call NeighborList.size()) + 1;
     // uint16_t linkedNeighbors[size];
      
        uint16_t i = 0;       
        Neighbor temp;
        uint16_t size = call Neighbors.size();
        uint16_t linkedNeighbors [size +1];
        if(!call Neighbors.isEmpty()){
          for (i = 0; i < size; i++) 
          {
            temp = call Neighbors.get(i);
            linkedNeighbors[i] = temp.nodeID;
          }
          linkedNeighbors[size] =0;

     // Make our LSP packet and flood it through Broadcast
     //Current,TTL20,LINKSTATE prot, payload = array
     makePack(&LSP,TOS_NODE_ID,AM_BROADCAST_ADDR,20,PROTOCOL_LINKSTATE,seqNumber++,
        (uint8_t*) linkedNeighbors,(uint16_t) sizeof(linkedNeighbors));
     //push pack into our pack list
     //   - May need to check isKnown for seen LSP packs later/ or make new function
     insertPack(LSP);
     call Sender.send(LSP,AM_BROADCAST_ADDR);
     //dbg(ROUTING_CHANNEL, "LSPNode %d has been flooded\n",TOS_NODE_ID);
      }
  }

// THINK THIS CAN GO IN DMP LINKSTATE
 void printLSP(){
    LinkState lsp;
    uint16_t i,j;
    dbg(ROUTING_CHANNEL,"NODE %d LSP Table_______\n",TOS_NODE_ID);
    for (i = 0; i < call RouteTable.size(); i++){
      lsp = call RouteTable.get(i);
      dbg(GENERAL_CHANNEL, "LSP from %d, Cost: %d, NextHop: %d, Seq: %d, neighbor size: %d\n",
        lsp.node, lsp.cost, lsp.nextHop, lsp.seq, lsp.arrLength);
      for(j = 0; j < lsp.arrLength; j++){
        dbg(GENERAL_CHANNEL, "Neighbor at %d\n",lsp.neighbors[j]);
      }
    }
    dbg(GENERAL_CHANNEL, "RouteTable size is %d\n", call RouteTable.size());
  }
 void Dijkstra(uint8_t Destination, uint8_t Cost, uint8_t NextHop)
    {
      uint16_t i, j, k, l;
      LinkState ConfirmedNode, TentativeNode,  NextNode, Confirmedgray, tentativeshorter, Confirmedblack;
      //bool isValid;

      dbg(ROUTING_CHANNEL, "DIJKSTRA -----\n");
     //1. initialize the confirmed list with an empty for myself
     //entry has a cost of 0
      //set unchecked node distance to infinity
       //For the node just added to the Confirmed list in the previous step, call it node Next and select its LSP
       // next= TOS_NODE_ID-1;
        ConfirmedNode.node = Destination; // destination = TOS_NODE_ID
        ConfirmedNode.cost = Cost; // cost =0
        ConfirmedNode.nextHop= NextHop; // NextHop = TOS_NODE_ID
        //ConfirmedNode.isValid = TRUE;
        //confirmedlist[next] = ConfirmedNode;
        call Confirmed.pushfront(ConfirmedNode);   

        if(ConfirmedNode.node != TOS_NODE_ID){
          for(i =0; i< call RouteTable.size(); i++){
            NextNode = call RouteTable.get(i);
            if(NextNode.node == Destination){
                for(j = 0; j< NextNode.arrLength; j++){
                  // If Neighbor is currently on neither the Confirmed nor tentative list
                  //then add (Neighbor, Cost, nexthop) to the tentative list where NextHop is the direction I go reach Next
                  if(NextNode.neighbors[j]>0){
                    ConfirmedNode.isValid = FALSE;
                    TentativeNode.isValid= FALSE;

                    while(! call Tentative.isEmpty())
                    {
                        for(k= 0; k< NextNode.arrLength; k++){
                          NextNode= call Tentative.get(i);
                          //If Neighbor is currently on Tentative list
                          if(NextNode.node == NextNode.neighbors[k]){
                             TentativeNode.isValid= TRUE; 
                          ////Cost is less then currently less than the currently listed cost
                              if(Confirmedgray.cost > NextNode.cost){
                          //for Neighbor, then replace the current entry with (Neighbor, Cost, Nexthop)
                         //where nexthop is the direction I go to reach Next
                                tentativeshorter = call Tentative.remove(k);
                                tentativeshorter.cost= NextNode.cost;
                                tentativeshorter.nextHop= NextNode.nextHop;
                                call Tentative.pushfront(tentativeshorter);
                                TentativeNode.isValid= TRUE;

                              }
                          }
                        }
                    }
                  }
                }
              }
            }
          }
          dbg(ROUTING_CHANNEL, "ROUTING Table \n");
          for(l = 0; l < call Confirmed.size(); l++)
          {
              Confirmedblack = call Confirmed.get(l);
              dbg(ROUTING_CHANNEL, "Dest: %d,  Cost: %d ,  Next: %d \n",  Confirmedblack.node, Confirmedblack.cost, Confirmedblack.nextHop);
          }

}

    /*void Dijkstra(uint8_t Destination, uint8_t Cost, uint8_t NextHop)
    {
      uint16_t i, j;
      uint8_t next;
      uint8_t path;
      uint8_t min; // =INFINITY;
      uint16_t size;
      uint16_t distance[MAXNODE];
      bool isValid;
      min= INFINITY;

      dbg(ROUTING_CHANNEL, "DIJKSTA -----");

      //int cost[MAXNODE][MAXNODE];
      uint16_t confirmedlist[MAXNODE];
      uint16_t tentativelist[MAXNODE];
      LinkState ConfirmedNode, TentativeNode,  NextNode; // VisitConfirm, VisitTentative;
      Neighbor nearNeighbors;
      //size = call RouteTable.size();
     //1. initialize the confirmed list with an empty for myself
     //entry has a cost of 0
      //set unchecked node distance to infinity
      for( i= 0; i <call RouteTable.size(); i++){
        confirmedlist.Cost[i] = INFINITY;
        tentativelist.Cost[i] = INFINITY;
        confirmedlist.isValid= FALSE;
        tentativelist.isValid= FALSE;
        tentativelist.Cost[i] = INFINITY;
       }

       //For the node just added to the Confirmed list in the previous step, call it node Next and select its LSP
        next= TOS_NODE_ID-1;
        ConfrimedNode.node = Destination;
        ConfirmedNode.Cost = 0;
        ConfirmedNode.nextHop= NextHop;
        ConfirmedNode.isValid = TRUE;
        //confirmedlist[next] = ConfirmedNode;
        call Confrimed.pushfront(ConfirmedNode);   

        if(Destination != TOS_NODE_ID){
          for(i =0; i< call RouteTable.size(); i++){
            NextNode = call RouteTable.get(i);
            if(NextNode.node = Destination){
              //3. 
              //  a. If Neighbor is currently on neither the Confirmed nor tentative list
              //then add (Neighbor, Cost, nexthop) to the tentative list where NextHop is the direction I go reach Next
                if(confirmedlist[i].isValid == FALSE && tentativelist[i].isValid == FALSE){
                    TentativeNode.node = i+1;
                    TentativeNode.nextHop= path;
                    tentativelist.isValid= TRUE;
                    call Tentative.pushfront(TentativeNode);
                }

                // b. If Neighbor is currently on Tentative list and Cost is less then currently less than the currently listed cost
                //    for Neighbor, then replace the current entry with (Neighbor, Cost, Nexthop)
                      //where nexthop is the direction I go to reach Next
                 if(tentativelist[i].isValid == FALSE && TentativeNode.Cost < tentativelist[i]){
                    TentativeNode.node = i+1;
                    TentativeNode.nextHop= path;
                    tentativelist.isValid= TRUE;
                    call Tentative.pushfront(TentativeNode);
                }
              }
            }
          }
          //4
          //if the tentative is empty then stop
          if(call Tentative.isEmpty()){
            return;
          }
          //if the tentative isn't empty then pick the empty from Tentative list with the lowest Cost
          if(!(call Tentative.isEmpty()))
          {
            for(i =0 ; i< call RouteTable.size(); i++){
              if(tentativelist[i].isValid==FALSE && tentativelist[i].Cost < min ){
                min =tentativelist[i].Cost;
                j= i;
              }
            }
          //  return j;
         // moved to Confirmed List 
         //(move lowest Cost from Tentative list to Confrimed List)
        ConfrimedNode.node = tentativelist[next].node;
        ConfirmedNode.Cost = tentativelist[next].Cost;
        ConfirmedNode.nextHop= tentativelist[next].nextHop;
        ConfirmedNode.isValid = TRUE;
        //confirmedlist[next] = ConfirmedNode;
        call Confrimed.pushfront(ConfirmedNode);   

          }
        }
    */


    }