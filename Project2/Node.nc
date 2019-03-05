
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
#define INFINITY 9999
#define MAX 20



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
typedef struct LinkState {
    nx_uint16_t neighbors[64]; // current list of neighbors
    nx_uint16_t arrLength;
    nx_uint16_t node; 
    nx_uint16_t cost; 
    nx_uint16_t seq;
    nx_uint16_t nextHop;
    //bool isValid;
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
   uses interface List<LinkState> as Tentative;
   uses interface List<LinkState> as Confirmed;
   uses interface List<LinkState> as RouteTable;
   uses interface List<LinkState> as routeTemp;
   //uses interface List<LinkState> as routeTemp;
   // New Timer for LSP 
   uses interface Timer<TMilli> as lspTimer; // fires and call function to create LSP packet
   uses interface Hashmap<int> as tableroute; // for out Dijkstras algorithm

}


implementation{
   pack sendPackage;
   uint16_t seqNumber = 0; 
   uint16_t lspCount = 0;
   Neighbor NewNeighbor;
   Neighbor TempNeighbor;
   uint16_t minDist(uint16_t dist[], bool sptSet[]);

   // Prototypes

   bool isKnown(pack *p);  // already seen function
   void insertPack(pack p); // push into list
   void neighborList(); // neighbor list
 
   // ---------Project 2 ------------//
   void makeLSP();
   void Dijkstra();
   uint16_t minDist(uint16_t dist[], bool sptSet[]);
   //void Dijkstra(uint8_t Destination, uint8_t Cost, uint8_t NextHop);
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
        if (temp.life > 3) {
          line = call Neighbors.remove(i);
          call Neighbors.remove(i); 
          //dbg(NEIGHBOR_CHANNEL,"Neighbor %d has EXPIRED and DROPPED from Node %d\n",line.nodeID,TOS_NODE_ID);
          //call DroppedNeighbors.pushfront(line);
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
        //makeLSP();
       // Dijkstra();
     
       if(lspCount < 17 && lspCount %3 == 2 && lspCount > 1){
          makeLSP();
       }
       if(lspCount == 17)
          Dijkstra();                          
   }


   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         //makeLSP();
         // Call timer to fire at intervals between 
         call periodicTimer.startPeriodicAt(1,1000); //1000 ms
         //call periodicTimer.startPeriodic(1000);
         //call lspTimer.startPeriodic(1000);
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      LinkState LSP;
      LinkState temp;
      bool match;
      bool flag;
      uint16_t i =0;
      uint8_t lsSize =0;
      uint16_t size;
    //dbg(FLOODING_CHANNEL, "Packet Received\n"); 
  if(len==sizeof(pack))
  {
     pack* myMsg=(pack*) payload;
    if (myMsg->TTL == 0 || isKnown(myMsg)){}
    
    else if(myMsg->dest == AM_BROADCAST_ADDR ) //&& (myMsg->protocol == PROTOCOL_PING || myMsg->protocol == PROTOCOL_PINGREPLY))
    { 
       if (myMsg->protocol == PROTOCOL_PING)
        {
           makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
            insertPack(sendPackage);
            call Sender.send(sendPackage, myMsg->src);
        } 
        else if (myMsg->protocol == PROTOCOL_PINGREPLY)
        {       
           flag = FALSE;
           size = call Neighbors.size();
            for(i = 0; i < size; i++)
            {       
               TempNeighbor = call Neighbors.get(i);
                if(TempNeighbor.nodeID == myMsg->src)
                {       
                   TempNeighbor.life = 0;
                    flag = TRUE;
                     break;
                }
            }
        }
        // If neighbor is not found in our list then it is New and need to add it to the list
        if(!flag) 
        { // No Match                   
         //           dbg(NEIGHBOR_CHANNEL, "New Neighbor %d found and adding to our list\n", myMsg->src);           
          if(call DroppedNeighbors.isEmpty())
          {
            NewNeighbor = call DroppedNeighbors.popfront();  //Get new neighbor                   
            NewNeighbor.nodeID =  myMsg->src;  // add src id                    
            NewNeighbor.life = 0;  // reset life
            call Neighbors.pushback(NewNeighbor);  // push into list
             //makeLSP();
            //dbg(GENERAL_CHANNEL, "pushback New Neighbor!\n");
          }
          else
          {
              NewNeighbor = call DroppedNeighbors.popfront();
              NewNeighbor.nodeID = myMsg->src;
              NewNeighbor.life = 0;
              call Neighbors.pushback(NewNeighbor);
          }
        }
    } 
    // ---------------- PROJECT 2 -------------------//
   // Go here After flooding LSP/ calculate route
  /*  Linkstate Protocol
      Checks to see if LSP already has copy
       If not Store LSP
        If it does -> compare seq # and store larger seq #
        If received LSP is newest, send that copy to all its neighbors and they do same
       >most recent LSP eventually reaches all nodes
  */
    else if(myMsg->dest == AM_BROADCAST_ADDR && myMsg->protocol == PROTOCOL_LINKSTATE)
    {
      //  //Check for LSP and current node match
      // If node already has copy of LSP
        if (TOS_NODE_ID == myMsg->src)
        {
          ////dbg(ROUTING_CHANNEL, "Match found. Dont Flood pack\n");
           match = TRUE;
        }
        else 
        {
          LSP.node = myMsg->src;
          LSP.cost = MAX_TTL - myMsg->TTL;
         // LSP.nextHop = myMsg->src;//not tos_node
          LSP.seq = myMsg->seq; 

          while (myMsg->payload[i] > 0)
          // //Fill the LSP tables directly connected neighbors
          {
              LSP.neighbors[i] = myMsg->payload[i];
              lsSize++;
              i++;
          }
        }
      if(!match)
      {
          LSP.arrLength = lsSize;
          call RouteTable.pushfront(LSP);
          makePack(&sendPackage, myMsg->src, AM_BROADCAST_ADDR, myMsg->TTL - 1, PROTOCOL_LINKSTATE, myMsg->seq, (uint8_t*) myMsg->payload, (uint8_t) sizeof(myMsg->payload));
          insertPack(sendPackage);
          call Sender.send(sendPackage, AM_BROADCAST_ADDR);
      }
    }

      /////BEGIN CHECKING FLOODING PROTOCOLS////

      // PROTOCOL_PING: packet was pinged but no reply

    else if(TOS_NODE_ID == myMsg->dest && myMsg->protocol == PROTOCOL_PING)
    {
      dbg(FLOODING_CHANNEL,"Packet #%d arrived from %d with payload: %s\n", myMsg->seq, myMsg->src, myMsg->payload);
    // dont push PROTOCOL_CMD into list, will not allow same node to send multiple pings     
      dbg(FLOODING_CHANNEL,"Ping replying to %d\n", myMsg->src);
      //// increase sequence id number
      seqNumber++;
        for(i = 0; i < call Confirmed.size(); i++)
         {
            temp = call Confirmed.get(i);
             if (temp.node == myMsg->src)
              {
              // //makepack with myMsg->src as destination 
               makePack(&sendPackage, TOS_NODE_ID, temp.nextHop, MAX_TTL, PROTOCOL_PINGREPLY, seqNumber, ((uint8_t *)myMsg-> payload), PACKET_MAX_PAYLOAD_SIZE);
                // Push into seen/sent package list
               insertPack(sendPackage);
               call Sender.send(sendPackage, AM_BROADCAST_ADDR);
               break;
              }
          }
          
        insertPack(sendPackage);
        //Send new packet
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
    }
    //// PROTOCOL PINGREPLY: Packet at correct destination; Stop sending packet
    else if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PINGREPLY)
    {
       dbg(FLOODING_CHANNEL, "PING REPLY RECEIVED FROM %d\n ",myMsg->src);
    }
    // Packet does not belong to current node 
    // Flood Packet with TTL - 1
    else
    {
        for(i = 0; i < call Confirmed.size(); i++)
        {       
            temp = call Confirmed.get(i);
            if (temp.node== myMsg->dest)
            {       
              //dbg(FLOODING_CHANNEL, "Packet from %d, intended for %d is being Rebroadcasted.\n", myMsg->src, myMsg->dest);
                makePack(&sendPackage, myMsg->src, temp.nextHop, myMsg->TTL-1, myMsg->protocol, myMsg->seq, ((uint8_t *)myMsg-> payload), PACKET_MAX_PAYLOAD_SIZE);
                insertPack(sendPackage);
                call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                 break;
             }
        }
     }
    return msg;
  } 
    dbg(FLOODING_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
}


event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
    uint16_t i;
    LinkState ls;
    uint16_t dest;
     dbg(GENERAL_CHANNEL, "PING EVENT \n");
      for (i = 0; i < call Confirmed.size(); i++){
        ls = call Confirmed.get(i);
        if(ls.node == destination){
          dest = ls.nextHop;
        }

      }
      //sendPackage.seq = sendPackage.seq + 1;
      //makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, sendPackage.seq, payload, PACKET_MAX_PAYLOAD_SIZE);
      makePack(&sendPackage, TOS_NODE_ID, destination, 20, 0, seqNumber+1, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR); // send to destination
      //seqNumber = seqNumber + 1;
      
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
      dbg(ROUTING_CHANNEL, "Print Route of node:%d\n",TOS_NODE_ID);
      for(i =0; i < call Confirmed.size(); i++){
            routing=  call Confirmed.get(i);
            dbg(ROUTING_CHANNEL, "--The Destination is %d\n  | The Cost is : %d\n  | The next hop is %d\n", routing.node, routing.cost, routing.nextHop); //add i 
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

   //Helper function to find the vertex with min distance, from set of vertices Not included in shortest path
    uint16_t minDist(uint16_t Cost[], bool isValid[]){
        uint16_t min = INFINITY;  // min value
        uint16_t minIndex =0; //changing number -> change value of nexthop
        uint16_t i;

        for(i = 0; i < MAX; i++){
            if(isValid[i] == FALSE && Cost[i] < min) // was < min
                //min = Cost[i]; // changed it based on CSE100 Minheap (lab14)
                minIndex = i;
               min = Cost[i];
        }
        return minIndex;
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
     makeLSP();        
   }   
   /* makeLSP()
    *  Check Neighbor List
    *  Make array of neighbors or cost ?
    *  Make pack, broadcast, linkstate protocol, array payload
   */
   void makeLSP(){
      pack LSP;
   
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
     makePack(&LSP,TOS_NODE_ID,AM_BROADCAST_ADDR,MAX_TTL-1,PROTOCOL_LINKSTATE,seqNumber+1,
        (uint8_t*) linkedNeighbors,(uint16_t) sizeof(linkedNeighbors));
     //push pack into our pack list
     insertPack(LSP);
     call Sender.send(LSP,AM_BROADCAST_ADDR);
     //dbg(ROUTING_CHANNEL, "LSPNode %d has been flooded\n",TOS_NODE_ID);
      }
  }


 void printLSP(){
    LinkState lsp;
    uint16_t i,j;
    dbg(ROUTING_CHANNEL,"NODE %d LSP Table_______\n",TOS_NODE_ID);
    for (i = 0; i < call RouteTable.size(); i++){
      lsp = call RouteTable.get(i);
      dbg(GENERAL_CHANNEL, "Dest: %d, Cost: %d, NextHop: %d, Seq: %d, neighbor size: %d\n",
        lsp.node, lsp.cost, lsp.nextHop, lsp.seq, lsp.arrLength);
      for(j = 0; j < lsp.arrLength; j++){
        //dbg(GENERAL_CHANNEL, "Neighbor at %d\n",lsp.neighbors[j]);
        if(lsp.neighbors[j] > 0)
          dbg(GENERAL_CHANNEL, "%d\n", lsp.neighbors[i]);
      }
    }
   // dbg(GENERAL_CHANNEL, "RouteTable size is %d\n", call RouteTable.size());
  }

  /*
   *
   * Dijkstra single source shortest path using adjacency matrix
   * - Create shortest path tree set(sptSet) that keeps track of vertices included in shortest path tree.
   *   Initially this set is empty.
   * - Assign distance value to all vertices. Initialize all dist values as INFINITY and 0 for source vertex.
   * - While sptSet doesn't include all vertices 
   *   1. pick vertex u not in sptSet and has min distance value
   *   2. Add u to sptSet
   *   3. Update distance value of all adjacent vertices of u. To update distance, iterate through all adjacent vertices
   *      For every v, if sum of distance of u(from srouce) and cost u->v, is less than dist v, then update dist of v.
   * source: geeks for geeks shortest path
  */

void Dijkstra(){
        uint16_t G[MAX][MAX];  //Tree: node/cost
        uint16_t i, path, V, E;
        uint16_t nextnode = TOS_NODE_ID - 1;

        uint16_t Cost[MAX]; // The output array. Cost[i] sill hold he shortest distancec from src to i

        bool isValid[MAX];  // isValid[i] will be true if vertex i is included in shortest path tree

        int base[MAX];  // Base/Parent array for shortest route calculation
                        // stores indexes of parent nodes
                        // Output array which is used to show constructed MST
        int num;
        
        LinkState nextnode2;
        // Initialize all distance as INFINITE and isValid (shortest path tree Set) as FALSE
        for(i = 0; i < MAX; i++){
            Cost[i] = INFINITY;
            isValid[i] = FALSE;
            base[i] = -1;   // base case
        }

        // Distance to own node is always 0
        Cost[nextnode] = 0;
        // Find shortest path for all vertices
        for(path = 0; path < MAX - 1; path++){
          // Picks min distance vertex from set of vertices not yet processed.
            V = minDist(Cost, isValid);
            // Marks chosen vertex as TRUE
            isValid[V] = TRUE;

            //Update Cost value of the adjacent vertices of v(chosen vertex)
            for(E = 0; E < MAX; E++){
                //Updates Cost[v] only if not in sptSet(not processed)
                if(!isValid[E] && G[V][E] != INFINITY && Cost[V] + G[V][E] < Cost[E]){
                    base[E] = V;
                    Cost[E] = Cost[V] + G[V][E];
                }
            }           
        }
        //Fill our hashmap
        for(i = 0; i < MAX; i++){
            num = i;
            //parent = -1 basecase; i/temp is source. (key, input)
            while(base[num] != -1  && base[num] != nextnode && num < MAX){
                num = base[num];
            }
            if(base[num] != nextnode){  // while parent[] != current node - 1
                call tableroute.insert(i + 1, 0);
            }
            else
            {
                call tableroute.insert(i + 1, num + 1);
            }
        }
        
        
      // Fill our Confirmed List
      if(call Confirmed.isEmpty()){
      for(i = 1; i <= 20; i++)
      {
        nextnode2.node = i;
        nextnode2.cost = G[TOS_NODE_ID][i];
        nextnode2.nextHop = call tableroute.get(i);
        call Confirmed.pushfront(nextnode2);
        //dbg(GENERAL_CHANNEL, "Our Confirmed list size:  %d\n", call Confirmed.size());
      }
    }
    
    }
    }

