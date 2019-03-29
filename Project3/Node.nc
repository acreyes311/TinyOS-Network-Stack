
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
#include "includes/socket.h"

#define INFINITY 9999
#define MAX 10

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

   uses interface Transport; //Project 3

   //Added Modules
   uses interface Timer<TMilli> as periodicTimer;  // Interface wired in NodeC.nc
   uses interface Random as Random; //used to avoid timer interruption/congestion
   //project 3 timer
   uses interface Timer<TMilli> as acceptTimer;
   uses interface Timer<TMilli> as writtenTimer;
   
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
   socket_t fd; // Global fd/socket

   // Prototypes
   bool isKnown(pack *p);  // already seen function
   void insertPack(pack p); // push into list
   void neighborList(); // neighbor list
 
   // ---------Project 2 ------------//
   void makeLSP();
   void Dijkstra();
   uint16_t minDist(uint16_t Cost[], bool isValid[]);
   //void Dijkstra(uint8_t Destination, uint8_t Cost, uint8_t NextHop);
   void printLSP();
   // ---------Project 3 -----------//
   void TCPProtocol(pack *myMsg);
   
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
    * Repackage ping with AM_BROADCAST_ADDR as destination   
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
          line = call Neighbors.remove(i);
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
        //makeLSP();
       // Dijkstra();
       
       if(lspCount < 17 && lspCount %3 == 2 && lspCount > 1){
          makeLSP();
       }
       if(lspCount == 17)
          Dijkstra();                          
   }
//based on Psuedocode
   //timer fired
    //  int newFd = accept();
    //  if newFd not NULL_SOCKET
    //    add to list of accepted sockets
    //  for all socket added
    //    read data and print
    /*
    event void acceptTimer.fired() {
          int i,size;
          socket_t newfd;
          newfd = call Transport.accept();
          size =call Socketlist.size();
          if(newfd != NULL){
            //if the socketsize is bigger than total sockets ize then print"socket is full"
            // else sockets are saved
            call Socketlist.pushback(fd);

            for(i=0; i<size; i++){
              //read data and print
              //maybe need to implement read in TransportP.nc
            }

          }
    }
    //based on Psuedocode
    //timer fired
    //  if all data has been written on the buffer empty
    //    create new data for the buffer
    //    //data is from 0 to [transfer]
    //subtract the amount of data you were able to write(fd, buffer, buffer len)
    event void writtenTimer.fired() {


    }
  */

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         //makeLSP();
         // Call timer to fire at intervals between 
         //call periodicTimer.startPeriodicAt(1,1000); //1000 ms
         call periodicTimer.startPeriodic(1000);
         //call lspTimer.startPeriodic(1000);
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
      uint16_t n;
      LinkState LSP;
      LinkState temp;
      LinkState dest;
      Neighbor lspNeighbor;
      uint16_t lsSize = 0;  // link state-> arrLength
      bool match;
      uint16_t nextHop;


      if(len==sizeof(pack))
      {

         pack* myMsg=(pack*) payload;  // Message of received package

         if(myMsg->TTL == 0) {
         // Drop packet if expired or seen 
         }
         if(isKnown(myMsg)) {
   //         dbg(FLOODING_CHANNEL,"Already seen PACKET #%d from %d to %d being dropped\n", myMsg->seq, myMsg->src, myMsg->dest);
         }

         // Neighbor Discovery or LSP entry
      if(AM_BROADCAST_ADDR == myMsg->dest) {            
   //       dbg(NEIGHBOR_CHANNEL, "Received a Ping Reply from %d\n", myMsg->src);
            // What protocol does the message contain
           switch(myMsg->protocol) {

                //PROTOCOL_PING SWITCH CASE //
                // repackage with TTL-1 and PING_REPLY PROTOCOL
               case PROTOCOL_PING:

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
                     //makeLSP();
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
                 
                 // dbg(ROUTING_CHANNEL, "Node: %d successfully received an LSP Packet from Node %d! Cost: %d \n", TOS_NODE_ID, myMsg->src, MAX_TTL - myMsg->TTL);
                  //dbg(ROUTING_CHANNEL, "Payload Array length is: %d \n", call RouteTable.size());
                  match = FALSE;
                  //Check for LSP and current node match
                  // If node already has copy of LSP
                  //if(myMsg->src == TOS_NODE_ID){
                    //dbg(ROUTING_CHANNEL, "Match found. Dont Flood pack\n");
                    // set flag = true
                   // match = TRUE;
                //  }
                  // if our table IS empty; Initialize and push into our RouteTable
                  if(call RouteTable.isEmpty()){
                    temp.node = TOS_NODE_ID;
                    temp.nextHop = TOS_NODE_ID;
                    temp.seq = myMsg->seq;
                    temp.arrLength = call Neighbors.size();
                    temp.cost = 0;
                    for(i = 0; i< temp.arrLength; i++) {
                      lspNeighbor = call Neighbors.get(i);
                      temp.neighbors[i] = lspNeighbor.nodeID;
                    }
                    call RouteTable.pushfront(temp);
                    //dbg(GENERAL_CHANNEL,"RouteTable size: %d\n",call RouteTable.size());
                   // dbg(GENERAL_CHANNEL,"msgTTL:%d, LSP cost:%d from:%d arrLen:%d\n", myMsg->TTL, LSP.cost, myMsg->src,LSP.arrLength);
                  }
                  // Else src is not current node                   
                  //else{
                  if(myMsg->src != TOS_NODE_ID){
                   // dbg(GENERAL_CHANNEL,"INSIDE IF(my->src != TOSNODE\n");
                    LSP.node = myMsg->src;
                    LSP.seq = myMsg->seq;
                    ///////////LSP.nextHop = myMsg->src; // not tos_node
                    LSP.cost = MAX_TTL - myMsg->TTL; // Took this many life to get here
                   // dbg(GENERAL_CHANNEL,"msgTTL:%d, LSP cost:%d from:%d\n",myMsg->TTL, LSP.cost, myMsg->src);
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
                        
                        // Check for most current LSP(SEQ) and Lowest cost
                        if((LSP.node == temp.node)&&(LSP.cost < temp.cost) &&(LSP.seq>=temp.seq)){
                           //dbg(GENERAL_CHANNEL,"INSIDE IF COST CHECK\n");
                          call RouteTable.popfront();  // Remove older LSP 
                        }
                        else if((LSP.node == temp.node) && (LSP.cost > temp.cost)&&(LSP.seq>=temp.seq)){
                          call routeTemp.pushfront(call RouteTable.front());
                          call RouteTable.popfront();
                        }
                        
                        else {
                          //dbg(GENERAL_CHANNEL,"INSIDE ELSE CHECK \n");
                          call routeTemp.pushfront(call RouteTable.front());
                          call RouteTable.popfront();
                        }
                      }
                        
                        while(!call routeTemp.isEmpty()){
                          //dbg(GENERAL_CHANNEL,"INSIDE WHILE 2 !!!\n");
                          call RouteTable.pushfront(call routeTemp.front());
                          call routeTemp.popfront();
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
 
                      if(call RouteTable.isEmpty()){                    
                        call RouteTable.pushfront(LSP);
                      }
                     // printLSP();
                      seqNumber++;
                      makePack(&sendPackage, myMsg->src, AM_BROADCAST_ADDR, myMsg->TTL-1, PROTOCOL_LINKSTATE,
                        seqNumber, (uint8_t*)myMsg->payload, (uint8_t)sizeof(myMsg->payload));
                      insertPack(sendPackage);
                      call Sender.send(sendPackage,AM_BROADCAST_ADDR);
                      //break;

                    }
                    //If no match to protocol LINKSTATE
                  
                    //dbg(GENERAL_CHANNEL,"AT END OF LS SWITCH!!!\n");
                    if(!match){ 
                    //             
                    }
                    //break;
                  }
                  break;  // break Case LINKSTATE                        
            }
          }

          // ---------NOT ENTERING HERE ------------
          // Reached Destination
       if(myMsg->dest == TOS_NODE_ID) //|| myMsg->protocol == PROTOCOL_PINGREPLY)) 
         {
            dbg(FLOODING_CHANNEL,"Packet #%d arrived from %d with payload: %s\n", myMsg->seq, myMsg->src, myMsg->payload);

            // Protocol Ping forwards to nextHop from our Confirmed List
            if( myMsg->protocol == PROTOCOL_PING ){

            // PROTOCOL_PING: packet was pinged but no reply
            //if(myMsg->protocol == PROTOCOL_PING) {
              nextHop = 0;
               dbg(FLOODING_CHANNEL,"Ping replying to %d\n", myMsg->src);
               //makepack with myMsg->src as destination              
               makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, seqNumber, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
               seqNumber++;   // increase sequence id number
               // Push into seen/sent package list
               insertPack(sendPackage);
               dbg(GENERAL_CHANNEL, "BEFORE dest.nextHOP\n");
               // Get our next Hop
               for (n = 0; n < call Confirmed.size(); n++){
                dest = call Confirmed.get(n);
                if(myMsg->src == dest.node){
                  nextHop = dest.nextHop;
                }
               }
               // Send new packet
               call Sender.send(sendPackage, nextHop); // Send to nextHop
               //call Sender.send(sendPackage, AM_BROADCAST_ADDR);               
            }

            // PROTOCOL PINGREPLY: Packet at correct destination; Stop sending packet
            if(myMsg->protocol == PROTOCOL_PINGREPLY) {
               dbg(FLOODING_CHANNEL, "PING REPLY RECEIVED FROM %d\n ",myMsg->src);
            }
            if(myMsg->protocol == PROTOCOL_TCP){
              TCPProtocol(myMsg);
            }

         }
      
         // Packet does not belong to current node 
         // Flood Packet with TTL - 1
         // broadcast to neighbors
         else {
          uint16_t k = 0;
          uint16_t snd = 0;
          LinkState tempDest;

          makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
               //makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
        //       dbg(FLOODING_CHANNEL, "Packet from %d, intended for %d is being Rebroadcasted.\n", myMsg->src, myMsg->dest);
            insertPack(sendPackage);   // Packet to be inserted into seen packet list
            for (k = 0; k < call Confirmed.size(); k++) {
              tempDest = call Confirmed.get(k);
              if(myMsg->dest == tempDest.node) {
                snd = tempDest.nextHop;
                //call Sender.send(sendPackage, tempDest.nextHop);
              }
            }
            call Sender.send(sendPackage,snd);
            //call Sender.send(sendPackage, AM_BROADCAST_ADDR);  // Resend packet
          } 
         //dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         return msg;
      }
      
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   // Try retrieving from hashmap tableroute get
   
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
      makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, seqNumber+1, payload, PACKET_MAX_PAYLOAD_SIZE);
      // Changed from BROADCAST
      insertPack(sendPackage);
      call Sender.send(sendPackage, dest);
      //if(call tableroute.get(destination)) {
        //call Sender.send(sendPackage, call tableroute.get(destination)); // send to destination
    //}
     // seqNumber = seqNumber + 1;
      
   }

   event void CommandHandler.printNeighbors(){

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

   /* ----- Set Test Server -----
    * Initiates server at node[address] and binds it to [port]
    * Listens for connections
    * If accepted a new socket is made for that connection and server continues to listen
   */
   event void CommandHandler.setTestServer(uint16_t port){
    socket_addr_t address;
    //socket_t fd;  // global fd up top

    dbg(GENERAL_CHANNEL, "inside setTestServer -- Initializing Server\n");

    address.addr = TOS_NODE_ID;
    address.port = port;

    fd = call Transport.socket();


    if(call Transport.bind(fd, &address) == SUCCESS && call Transport.listen(fd) == SUCCESS)
      dbg(TRANSPORT_CHANNEL, "Socket %d is Listening.\n", fd);
    else
      dbg(TRANSPORT_CHANNEL, "Unable to set socket %d.\n", fd);

   }

   /* ----- Set Test Client -----
    * Initiates client and binds it to [srcPort], attempts to make connection to [dest] at port [destPort]
    * After Connection, send [transfer] bytes to server
   */
   event void CommandHandler.setTestClient(uint16_t dest, uint16_t srcPort, uint16_t destPort, uint16_t transfer){
    socket_addr_t address;  // socket address
    socket_addr_t serverAdr;  // server address

    dbg(TRANSPORT_CHANNEL, "Inside setTestClient -- Testing Client.\n");

    fd = call Transport.socket();

    // Source and source port
    address.addr = TOS_NODE_ID;
    address.port = srcPort;
    // Destination and dest port
    serverAdr.addr = dest;
    serverAdr.port = destPort;

    if(call Transport.bind(fd, &address) == SUCCESS) {
      dbg(TRANSPORT_CHANNEL, "Client success.\n");
    }
    call Transport.connect(fd, &serverAdr);

    dbg(TRANSPORT_CHANNEL, "Node %d is client with source port %d, and dest %d at their port %d.\n",
      TOS_NODE_ID, srcPort, dest, destPort);

   }

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
        uint16_t minIndex = 0; //changing number -> change value of nexthop
        uint16_t i;

        for(i = 0; i < MAX; i++){
            if(isValid[i] == FALSE && Cost[i] < min) // was < min
               // min = Cost[i]; // changed it based on CSE100 Minheap (lab14)
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
     //makeLSP();        
   }   
   /* makeLSP()
    *  Check Neighbor List
    *  Make array of neighbors or cost 
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
     makePack(&LSP,TOS_NODE_ID,AM_BROADCAST_ADDR,MAX_TTL-1,PROTOCOL_LINKSTATE,++seqNumber,
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
   * - Create shortest path tree set(isValid) that keeps track of vertices included in shortest path tree.
   *   Initially this set is empty.
   * - Assign distance value to all vertices. Initialize all dist values as INFINITY and 0 for source vertex.
   * - While sptSet doesn't include all vertices 
   *   1. pick vertex V not in sptSet and has min distance value
   *   2. Add V to isValid
   *   3. Update distance value of all adjacent vertices of V. To update distance, iterate through all adjacent vertices
   *      For every E, if sum of distance of V(from srouce) and cost V->E, is less than dist E, then update dist of E.
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
      for(i = 1; i <= 10; i++)
      {
        nextnode2.node = i;
        nextnode2.cost = G[TOS_NODE_ID][i];
        nextnode2.nextHop = call tableroute.get(i);
        call Confirmed.pushfront(nextnode2);
        //dbg(GENERAL_CHANNEL, "Our Confirmed list size:  %d\n", call Confirmed.size());
      }
    }
    
    }

// ----------- Project 3 -------------
  // Iterate through list and find index that has Socket with matching port. Then Check Flag

  // Flag 1: Received SYN from src, Send SYN_ACK, change state to SYN_RCVD
  // Flag 2: Received SYN_ACK from src, Send ACK, change state to ESTABLISHED
  // FLAG 3: Received ACK from src, change state to ESTABLISHED
  // After flag 3 both client and server states are established and ready to transmit data
  void TCPProtocol(pack *myMsg) {
    socket_store_t* receivedSocket;
    socket_store_t tempSocket;
    int i,j;
    LinkState dest;
    uint16_t next;

    // SYN_ACK Packet
    pack SynAckPack;

    receivedSocket = myMsg->payload;

    //Get our Next Destination
    // ------------------ CHANGE TO SWITCH TO HANDLE 3-WAY HANDSHAKE ---------------
    //Find right socket
    for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
      tempSocket = call Transport.getSocket(i);
      // Check for Port and Source; Listening; And Check Flag 1 for SYN.
      // If Found send a SYN_ACK
      if(receivedSocket->flag == 1) {
        // Update Socket State and Bind
        tempSocket.flag = 2;
        tempSocket.dest.port = receivedSocket->src;
        tempSocket.dest.addr = myMsg->src;
        tempSocket.state = SYN_RCVD;
        call Transport.bind(tempSocket.fd, tempSocket); // Change to setSocket/Update

        //Make our SYN_ACK
        makePack(&SynAckPack, TOS_NODE_ID, myMsg->src, myMsg->TTL, PROTOCOL_TCP, myMsg->seq, &tempSocket, (uint8_t)sizeof(tempSocket));

        // Get Our Next Destination
        for(j = 0; j < Confirmed.size();j++){
          dest = call Confirmed.get(j);
          if (SynAckPack.dest == dest.node){
            next = dest.nextHop;
          }
        }

        dbg(TRANSPORT_CHANNEL,"SYN packet received from Node %d port %d, replying SYN_ACK.\n", myMsg->src, receivedSocket->src);
        //if(call tableroute.get(tempSocket.dest.addr))
          //call Sender.send(SynAckPack, call tableroute.get(tempSocket.dest.addr)); //brimo
        //else
          //dbg(TRANSPORT_CHANNEL, "Cant find route to client.\n");
        call Sender.send(SynAckPack,next);  //aye
        
      }//end if

      // Flag2: SYN_ACK packet
      else if(receivedSocket->flag == 2){
        // Pack to reply to the SYN_ACK; Connection has been ESTABLISHED
        pack AckPack;

        dbg(TRANSPORT_CHANNEL,"Received SYN_ACK.\n");

        //Update Socket State and Bind
        tempSocket.flag = 3;
        tempSocket.dest.port = receivedSocket->src;
        tempSocket.dest.addr = myMsg->src;
        tempSocket.state = ESTABLISHED;
        call Transport.bind(tempSocket.fd, tempSocket); // Change to setSocket/Update

        //Make ACK packet
        makePack(&AckPack, TOS_NODE_ID, myMsg->src, myMsg->TTL, PROTOCOL_TCP, myMsg->seq, &tempSocket, (uint8_t)sizeof(tempSocket));

        dbg(TRANSPORT_CHANNEL,"SYN_ACK received, connection ESTABLISHED, replying with ACK.\n");

        call Sender.send(AckPack, call tableroute.get(tempSocket.dest.addr));       


      }
      else if(receivedSocket->flag == 3){
        dbg(TRANSPORT_CHANNEL,"Received ACK.\n");

        tempSocket = call Transport.getSocket(i);

        tempSocket.state = ESTABLISHED;

        call Transport.bind(tempSocket.fd, tempSocket); // Change to setSocket/Update
      }
    }//end for
  }

    }



