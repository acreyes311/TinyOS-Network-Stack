
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
//#include "includes/tcp_pack.h"

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

   // ----- Project 3 ------
   uses interface List<socket_store_t> as Socketlist;
   uses interface List<socket_store_t> as modSockets;

}


implementation{
   pack sendPackage;
   uint16_t seqNumber = 0; 
   uint16_t lspCount = 0;
   Neighbor NewNeighbor;
   Neighbor TempNeighbor;
   socket_t fd; // Global fd/socket
   uint32_t TimeReceived; 
   uint32_t TimeSent;
   uint16_t globalTransfer;

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
      //call periodicTimer.startPeriodic(1000);

   }

   /*
    * neighborList() function Loops through our neighbor list if not empty
    * and increase the life/pings/life of each neighbor (number of pings since they were last heard)
    * Check list again for any Neighbor with life > 3 and drop them as expired. Add to Drop list
    * Repackage ping with AM_BROADCAST_ADDR as destination   
   */
   void neighborList() {
    pack package;
    char *msg;
    uint16_t size;
    uint16_t i = 0;
    uint16_t pings = 0;
    Neighbor line;//neighbornode
    Neighbor temp;
    size = call Neighbors.size();
    lspCount++;

    //Check to see if neighbors have been found
    if(!call Neighbors.isEmpty()) {
 //     dbg(NEIGHBOR_CHANNEL, "NeighborList, node %d looking for neighbor\n",TOS_NODE_ID);
      // Loop through Neighbors List and increase life/pings/age if not seen
      //  will be dropped every 5 pings a neighbor is not seen.
      for (i = 0; i < size; i++) {
        temp = call Neighbors.get(i);
        temp.life = temp.life + 1;
        pings = temp.life;
        //call Neighbors.remove(i);
        //call Neighbors.pushback(line);
      
      //for (i = 0; i < size; i++) {
       // temp = call Neighbors.get(i);
        //life = temp.life;

        // Drop expired neighbors after 7 pings and put in DroppedList
        if (pings > 7) {
          lspCount = 0;
          line = call Neighbors.remove(i);
          call Neighbors.popback();
          //dbg(NEIGHBOR_CHANNEL,"Neighbor %d has EXPIRED and DROPPED from Node %d\n",line.nodeID,TOS_NODE_ID);
          call DroppedNeighbors.pushfront(line);
          i--;
          size--;
        }
      }
    }
    // After Dropping expired neighbors now Ping list of neighbors
    msg = "Message\n";
    // Send discovered packets, destination AM_BROADCAST
    makePack(&package, TOS_NODE_ID, AM_BROADCAST_ADDR,2,PROTOCOL_PING,1,(uint8_t*)msg,(uint8_t)sizeof(msg));
    insertPack(package);
    call Sender.send(package, AM_BROADCAST_ADDR);
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
       //if(lspCount > 1 && lspCount % 20 == 0 && lspCount < 61)
          Dijkstra();                          
   }

   
//based on Psuedocode
   //timer fired
    //  int newFd = accept();
    //  if newFd not NULL_SOCKET
    //    add to list of accepted sockets
    //  for all socket added
    //    read data and print
    
    //Returns the amount of data able to read from pass buffer
    event void acceptTimer.fired() {
      socket_store_t temp;
      uint8_t i, ind,avail;      
      bool found = FALSE;

      dbg(TRANSPORT_CHANNEL, "acceptTimer Fired!\n");

      fd = call Transport.accept(fd);

      for(i = 0; i < call Socketlist.size(); i++){
        temp = call Socketlist.get(i);

        if(temp.fd == fd && !found){
          found = TRUE;
          ind = i;
        }// end if
      }//end for

      if(found){
        temp = call Socketlist.get(ind);
        avail = call Transport.read(temp.fd,0,temp.lastWritten);
        dbg(TRANSPORT_CHANNEL,"Read Amount avail %d\n",avail);
      }// End if
    }// End acceptTimer()


    //based on Psuedocode
    //timer fired
    //  if all data has been written on the buffer empty
    //    create new data for the buffer
    //    //data is from 0 to [transfer]
    //subtract the amount of data you were able to write(fd, buffer, buffer len)

    //Returns amount of data able to write from the pass buffer
    event void writtenTimer.fired() {
      socket_store_t temp;
      uint8_t i, avail, ind;
      bool found = FALSE;

      dbg(TRANSPORT_CHANNEL,"writtenTimer Fired!\n");

      for(i = 0; i < call Socketlist.size(); i++){
        temp = call Socketlist.get(i);
        if(temp.fd == fd && !found){
          found = TRUE;
          ind = i;
        }//end if
      }//end for

      if(found){
        temp = call Socketlist.get(ind);
        while(globalTransfer > 0){
          avail = call Transport.write(fd,0,globalTransfer);
          globalTransfer = globalTransfer - avail;  // Is this done in write()?
          dbg(TRANSPORT_CHANNEL,"written Amount avail %d and globalTransfer %d\n",avail,globalTransfer);
        }//end while
      }//end if
    }// END writtenTimer()
  

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         //call periodicTimer.startPeriodic(10000 + (uint16_t)((call Random.rand16())%200));
         // Call timer to fire at intervals between 
         //call periodicTimer.startPeriodicAt(1,1000); //1000 ms
         call periodicTimer.startPeriodic(1000);
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
      LinkState replyDest;
      Neighbor lspNeighbor;
      uint16_t lsSize = 0;  // link state-> arrLength
      bool match;
      uint16_t nextHop;


      if(len==sizeof(pack))
      {

         pack* myMsg=(pack*) payload;  // Message of received package

         //if(myMsg->TTL == 0 ) {
         // Drop packet if expired or seen 
        // }
         
         //if(isKnown(myMsg)) {
   //         dbg(FLOODING_CHANNEL,"Already seen PACKET #%d from %d to %d being dropped\n", myMsg->seq, myMsg->src, myMsg->dest);
        //}
        if(myMsg->TTL == 0 || isKnown(myMsg)){
          //return msg;
        }
         // Neighbor Discovery or LSP entry
      else if(AM_BROADCAST_ADDR == myMsg->dest) {            

            // What protocol does the message contain
                // repackage with TTL-1 and PING_REPLY PROTOCOL

        if(myMsg->protocol == PROTOCOL_PING) {
                  makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                  insertPack(sendPackage); // Insert pack into our list
                  call Sender.send(sendPackage, myMsg->src);  // Send with pingreply protocol
                  //break;
        }// End Prot Ping       
        else if (myMsg->protocol == PROTOCOL_PINGREPLY){
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
                  }   
                    
        }// End Prot Ping Reply                
               
    
            // ---------------- PROJECT 2 -------------------//
                // Go here After flooding LSP/ calculate route
                /*  Linkstate Protocol
                  Checks to see if LSP already has copy
                  If not Store LSP
                  If it does -> compare seq # and store larger seq #
                  If received LSP is newest, send that copy to all its neighbors and they do same
                  ->most recent LSP eventually reaches all nodes
                */
                        
        else if(myMsg->protocol == PROTOCOL_LINKSTATE){         

                  flag = FALSE;
                  
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
                    temp.seq = 0;
                    temp.arrLength = call Neighbors.size();
                    temp.cost = 0;
                    for(i = 0; i< temp.arrLength; i++) {
                      lspNeighbor = call Neighbors.get(i);
                      temp.neighbors[i] = lspNeighbor.nodeID;
                    }
                    call RouteTable.pushfront(temp);
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
                        if((LSP.node == temp.node)&&(LSP.cost < temp.cost) ){
                           //dbg(GENERAL_CHANNEL,"INSIDE IF COST CHECK\n");
                          call RouteTable.popfront();  // Remove older LSP 
                          flag = TRUE;
                        }
                        else if((LSP.node == temp.node) && (LSP.cost > temp.cost)){
                          call routeTemp.pushfront(call RouteTable.front());
                          call RouteTable.popfront();
                          flag = TRUE;
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
                      }
 
                      if(call RouteTable.isEmpty()){                    
                        call RouteTable.pushfront(LSP);
                      }
                      else if(flag == FALSE){
                        call RouteTable.pushfront(LSP);
                      }
                     // printLSP();
                      seqNumber++;
                      makePack(&sendPackage, myMsg->src, AM_BROADCAST_ADDR, myMsg->TTL-1, PROTOCOL_LINKSTATE,
                        seqNumber, (uint8_t*)myMsg->payload, (uint8_t)sizeof(myMsg->payload));
                      insertPack(sendPackage);
                      call Sender.send(sendPackage,AM_BROADCAST_ADDR);
                      //break;

                    }// end if(call routetable isempty)
            }// End if PROT == LINKSTATE
            if(!flag && myMsg->protocol != PROTOCOL_LINKSTATE && myMsg->protocol != PROTOCOL_TCP){
              Neighbor tempN;
              NewNeighbor = call DroppedNeighbors.get(0);
              size = call Neighbors.size();

              for(i = 0; i < size; i++) {
                tempN = call Neighbors.get(i);
                if(myMsg->src == tempN.nodeID) {
                  match = TRUE;
                }
              }
              if (match == TRUE){}
              else {
                NewNeighbor.nodeID = myMsg->src;
                NewNeighbor.life = 0;
                call Neighbors.pushback(NewNeighbor);
              }
            }                         
          }         

          // Reached Destination
       else if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PING) //|| myMsg->protocol == PROTOCOL_PINGREPLY)) 
         {
          //if(myMsg->protocol == PROTOCOL_PING){
            dbg(FLOODING_CHANNEL,"Packet arrived from %d with payload: %s\n",myMsg->src, myMsg->payload);

            // Protocol Ping forwards to nextHop from our Confirmed List
              //Dijkstra();
              //nextHop = 0;
               dbg(FLOODING_CHANNEL,"Ping replying to %d\n", myMsg->src);
               //makepack with myMsg->src as destination              
               makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, seqNumber, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
               //seqNumber++;   // increase sequence id number
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
               /*
               for (n = 0; n < call Confirmed.size(); n++){
                dest = call Confirmed.get(n);
                if(myMsg->src == dest.node){
                  makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, seqNumber, (uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                  insertPack(sendPackage);
                  call Sender.send(sendPackage, dest.nextHop);
                  break;
                  //nextHop = dest.nextHop;
                }
               }
               */
               // Send new packet
               //dbg(ROUTING_CHANNEL,"pack for %d, sending to %d\n",myMsg->src, nextHop);
               call Sender.send(sendPackage, nextHop); // Send to nextHop
               //call Sender.send(sendPackage, AM_BROADCAST_ADDR);               
          }// End else if prot == PROT_PING

            // PROTOCOL PINGREPLY: Packet at correct destination; Stop sending packet
        else if(myMsg->protocol == PROTOCOL_PINGREPLY && myMsg->dest == TOS_NODE_ID) {
               dbg(FLOODING_CHANNEL, "PING REPLY RECEIVED FROM %d !!\n ",myMsg->src);
        }
        else if(myMsg->protocol == PROTOCOL_TCP && myMsg->dest == TOS_NODE_ID){
              TCPProtocol(myMsg);
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
            //dbg(FLOODING_CHANNEL, "Packet from %d, intended for %d is being Rebroadcasted.\n", myMsg->src, myMsg->dest);
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

      else{
      
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
      }
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
      
      /*
      makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      if(call tableroute.get(destination)){
        call Sender.send(sendPackage, call tableroute.get(destination));
      }
  */
      dbg(GENERAL_CHANNEL,"PING!!! dest %d Next Hop %d \n",destination, dest);
      makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      // Changed from BROADCAST
      //insertPack(sendPackage);
      call Sender.send(sendPackage, dest);      
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
    * Then Listens for connections
    * If accepted a new socket is made for that connection and server continues to listen
   */
   event void CommandHandler.setTestServer(uint16_t port){
    socket_addr_t address;
    //socket_t fd;  // global fd up top

    dbg(GENERAL_CHANNEL, "Inside setTestServer -- Initializing Server\n");

    address.addr = TOS_NODE_ID;
    address.port = port;

    fd = call Transport.socket();

    if(call Transport.bind(fd, &address) == SUCCESS && call Transport.listen(fd) == SUCCESS){
      dbg(TRANSPORT_CHANNEL, "Socket %d is Listening.\n", fd);
      //call acceptTimer.startOneShot(30000);
    }
    else
      dbg(TRANSPORT_CHANNEL, "Unable to set socket %d.\n", fd);

   }// End setTestServer


   /* ----- Set Test Client -----
    * Initiates client and binds it to [srcPort], attempts to make connection to [dest] at port [destPort]
    * After Connection, send [transfer] bytes to server
   */
   event void CommandHandler.setTestClient(uint16_t dest, uint16_t srcPort, uint16_t destPort, uint16_t transfer){
    socket_addr_t address;  // socket address
    socket_addr_t socketAdr,serverAdr;  // server address

    dbg(TRANSPORT_CHANNEL, "Inside setTestClient -- Testing Client.\n");

    // Get Socket fd
    fd = call Transport.socket();

    // Source and source port
    socketAdr.addr = TOS_NODE_ID;
    socketAdr.port = srcPort;

    //Bind Client socket to Socket Adddress
    if(call Transport.bind(fd, &socketAdr) == SUCCESS) {
      dbg(TRANSPORT_CHANNEL, "Client successfully binded.\n");
      // Destination and dest port
      serverAdr.addr = dest;
      serverAdr.port = destPort;

      //TimeSent = call LocalTime.getNow();
    if(call Transport.connect(fd,&serverAdr) == SUCCESS){
      //call writtenTimer.startOneShot(15000);
      dbg(TRANSPORT_CHANNEL,"Transport.connect SUCCESS\n");
    }
  }
    
    dbg(TRANSPORT_CHANNEL, "Node %d is client with source port %d, and dest %d at their port %d.\n",
      TOS_NODE_ID, srcPort, dest, destPort);

   }// End setTestClient


   // cmdClientClose([client address],[dest],[srcPort],[destPort])
   // Terminate Connection.
   // find fd associated with [clieant address],[srcPort],[destPort],[dest];
   //     close(fd)
   /*
   event void CommandHandler.ClientClose(uint8_t clientAddr, uint8_t srcPort, uint8_t destPort, uint8_t dest)  {
    int i;
    socket_store_t socket;
    socket_t fd;

    call Transport.close(fd);
   }
  */
  event void CommandHandler.ClientClose(uint8_t clientAddr, uint8_t srcPort, uint8_t destPort, uint8_t dest)  {
    pack Fin;
    socket_store_t temp, temp2;
    uint16_t i, next;
    LinkState destination;

    // Make FIN pack
    Fin.dest = dest;
    Fin.src = TOS_NODE_ID;
    Fin.seq = 1;
    Fin.TTL = MAX_TTL;

    //Get and Update Socket to CLOSED
    temp = call Socketlist.get(fd);
    temp.state = CLOSED;
    temp.flag = 6;
    temp.dest.port = destPort;
    temp.dest.addr = dest;

    while(!call Socketlist.isEmpty()){
      temp2 = call Socketlist.front();
      if(temp.fd == temp2.fd){
        call modSockets.pushfront(temp);
      }
      else{
        call modSockets.pushfront(temp2);
      }
      }// End While

      while(!call modSockets.isEmpty()){
        call Socketlist.pushfront(call modSockets.front());
        call modSockets.popfront();
      }

      for(i = 0; i <call Confirmed.size(); i++){
        destination = call Confirmed.get(i);
        if(Fin.dest == destination.nextHop){
          next = destination.nextHop;
        }
      }
      dbg(TRANSPORT_CHANNEL,"Sending FIN packet to %d\n",next);
      call Sender.send(Fin,next);
      dbg(TRANSPORT_CHANNEL, "Client Closed.\n");

    }
  

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}


   // ----------- Project 3 TCP PROTOCOL-------------
  // Iterate through list and find index that has Socket with matching port. Then Check Flag

  // Flag 1: Received SYN from src, Send SYN_ACK, change state to SYN_RCVD
  // Flag 2: Received SYN_ACK from src, Send ACK, change state to ESTABLISHED
  // FLAG 3: Received ACK from src, change state to ESTABLISHED
  // After flag 3 both client and server states are established and ready to transmit data

  void TCPProtocol(pack *myMsg) {
    socket_store_t* receivedSocket;
    socket_store_t tempSocket;
    socket_store_t stateSocket;
    socket_addr_t tempAddr;
    
    int i,j,k;
    uint8_t srcPort, destPort;
    LinkState dest;
    LinkState ls;
    uint16_t next;

    // SYN_ACK Packet
    pack SynAckPack;

    //tcp_pack* msg = (tcp_pack*) myMsg->payload;
    receivedSocket = myMsg->payload;
    tempAddr = receivedSocket->dest;


    // ------------------ CHANGE TO SWITCH TO HANDLE 3-WAY HANDSHAKE ---------------
    //Find right socket
    for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
      tempSocket = call Transport.getSocket(i);
      // Check for Port and Source; Listening; And Check Flag 1 for SYN.
      // If Found send a SYN_ACK
      if(receivedSocket->flag == 1){// && tempAddr.port == tempSocket.src && tempSocket.state == LISTEN && tempAddr.addr == TOS_NODE_ID) {
        // Update Socket State and Bind
        tempSocket.flag = 2;
        tempSocket.dest.port = receivedSocket->src;
        tempSocket.dest.addr = myMsg->src;
        tempSocket.state = SYN_RCVD;
        //call Transport.bind(tempSocket.fd, tempSocket); // Change to setSocket/Update
        call Transport.setSocket(tempSocket.fd, tempSocket);//update socketlist

        //Make our SYN_ACK
        //makePack(&SynAckPack, TOS_NODE_ID, myMsg->src, myMsg->TTL, PROTOCOL_TCP, myMsg->seq, &tempSocket, (uint8_t)sizeof(tempSocket));
        SynAckPack.dest = myMsg->src;
        SynAckPack.src = TOS_NODE_ID;
        SynAckPack.seq = myMsg->seq + 1;
        SynAckPack.TTL = myMsg->TTL;
        SynAckPack.protocol = PROTOCOL_TCP;

        //memcpy(dest, src, count)
        memcpy(SynAckPack.payload, &tempSocket, (uint8_t)sizeof(tempSocket));

        // Get Our Next Destination
        for(j = 0; j < call Confirmed.size();j++){
          dest = call Confirmed.get(j);
          if (SynAckPack.dest == dest.node){
            next = dest.nextHop;
          }
        }

        /*
        while (!Socketlist.isEmpty()){
          stateSocket = call Socketlist.front();
          if(stateSocket.fd == i) {
            stateSocket.state = SYN_RCVD;
            call localSocketList.pushfront(stateSocket);
          }
          else{
            call localSocketList.pushfront(stateSocket);
          }
        }
          while(!call localSocketList.isEmpty()){
            call Socketlist.pushfront(call localSocketList.front());
            call localSocketList.popfront();
          }
        */

        dbg(TRANSPORT_CHANNEL,"SYN packet received from Node %d port %d, replying SYN_ACK.\n", myMsg->src, receivedSocket->src);

          
        call Sender.send(SynAckPack,next); 
        return;
        
      }//end if
      //}// End for

      // Flag2: SYN_ACK packet
      if(receivedSocket->flag == 2){
        // Pack to reply to the SYN_ACK; Connection has been ESTABLISHED
        pack AckPack;

        //dbg(TRANSPORT_CHANNEL,"Received SYN_ACK.\n");
        tempSocket = call Transport.getSocket(i);
        //Update Socket State
        tempSocket.flag = 3;
        tempSocket.dest.port = receivedSocket->src;
        tempSocket.dest.addr = myMsg->src;
        tempSocket.state = ESTABLISHED;
        call Transport.setSocket(tempSocket.fd, tempSocket);
        //Make ACK packet
        //makePack(&AckPack, TOS_NODE_ID, myMsg->src, myMsg->TTL, PROTOCOL_TCP, myMsg->seq, &tempSocket, (uint8_t)sizeof(tempSocket));
        AckPack.dest = myMsg->src;
        AckPack.src = TOS_NODE_ID;
        AckPack.seq = myMsg->seq + 1;
        AckPack.TTL = myMsg->TTL;
        AckPack.protocol = PROTOCOL_TCP;

        memcpy(AckPack.payload,&tempSocket, (uint8_t)sizeof(tempSocket));

        dbg(TRANSPORT_CHANNEL,"SYN_ACK received, connection ESTABLISHED, replying with ACK.\n");

        //call Sender.send(AckPack, call tableroute.get(tempSocket.dest.addr));     
        // Get Our Next Destination
        for(j = 0; j < call Confirmed.size();j++){
          dest = call Confirmed.get(j);
          if (AckPack.dest == dest.node){
            next = dest.nextHop;
          }
        }  
        call Sender.send(AckPack, next);
        return;

      } // End flag == 2

     if(receivedSocket->flag == 3){
        uint8_t buff[1];
        
        tempSocket = call Transport.getSocket(i);
        dbg(TRANSPORT_CHANNEL,"Received ACK 3-Way Handshake Complete.\n");
        
      if(tempSocket.state == SYN_RCVD){
          call Socketlist.pushfront(tempSocket);
      }
      buff[0] = 1;
        //call Transport.
        call Transport.write(tempSocket.fd, buff,1);

        //update the state of the socket
        tempSocket.state = ESTABLISHED;
        call Transport.setSocket(tempSocket.fd, tempSocket);

        return;

      }// End flag == 3

      // Flag = 4 DATA packet
      if(receivedSocket->flag == 4){ 
        //Data received, now read it
        //DATA_ACK packet to acknowledge to other node that data has been received
        pack DATA_ACK;
        //Length of buffer same as value of lastWritten index in buffer
        uint16_t bufferLength = 8;
        //uint16_t bufferLength = myMsg->seq;

        //Read the buffer from the DATA packet.
        //bufferLength = call Transport.read(receivedSocket->fd,receivedSocket->sendBuff, bufferLength);
        call Transport.read(receivedSocket->fd,receivedSocket->sendBuff, bufferLength);
        dbg(TRANSPORT_CHANNEL,"Finished flag4.read().\n");

        for(j = 0; j< bufferLength; j++){
          printf("%d ",receivedSocket->sendBuff[j]);          
        }
        printf("\n");
        //Get current state of socket
        tempSocket = call Transport.getSocket(i);

        //update state of socket
        tempSocket.flag = 5;
        tempSocket.nextExpected = bufferLength + 1;

        call Transport.setSocket(tempSocket.fd, tempSocket);

        //Make DATA_ACK PACK
        DATA_ACK.dest = myMsg->src;
        DATA_ACK.src = TOS_NODE_ID;
        DATA_ACK.seq = myMsg->seq+1;
        DATA_ACK.TTL = myMsg->TTL;
        DATA_ACK.protocol = PROTOCOL_TCP;

        memcpy(DATA_ACK.payload, &tempSocket,(uint8_t)sizeof(tempSocket));

        dbg(TRANSPORT_CHANNEL,"DATA has been received and sending out DATA_ACK.\n");

        for(j = 0; j < call Confirmed.size();j++){
          dest = call Confirmed.get(j);
          if (DATA_ACK.dest == dest.node){
            next = dest.nextHop;
          }
        }//end j for  
        call Sender.send(DATA_ACK, next);
        return;
      }// end flag == 4

      // FLAG = 5 DATA_ACK
      if(receivedSocket->flag == 5){
        dbg(TRANSPORT_CHANNEL,"DATA_ACK received, DATA reached destination.\n");
        return;
      }//end flag == 5

      //flag = 6 receive Fin pack and close
      if(receivedSocket->flag == 6){
        dbg(TRANSPORT_CHANNEL,"FIN received.\n");
        while(!call Socketlist.isEmpty()){
          tempSocket = call Socketlist.front();
          call Socketlist.popfront();
          if(tempSocket.fd == i){
            tempSocket.state = CLOSED;
            call modSockets.pushfront(tempSocket);
          }//end if
          else {
            call modSockets.pushfront(tempSocket);
          }//end else
        }// end While
        while(!call modSockets.isEmpty()){
          call Socketlist.pushfront(call modSockets.front());
          call modSockets.popfront();
        }
        return;
      }//end flag = 6
    }//end for

  }// End TCPProtocol

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
     makePack(&LSP,TOS_NODE_ID,AM_BROADCAST_ADDR,MAX_TTL-1,PROTOCOL_LINKSTATE,seqNumber++,
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
  /*
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
      for(i = 1; i < 10; i++)
      {
        nextnode2.node = i;
        nextnode2.cost = G[TOS_NODE_ID][i];
        nextnode2.nextHop = call tableroute.get(i);
        call Confirmed.pushfront(nextnode2);
        //dbg(GENERAL_CHANNEL, "Our Confirmed list size:  %d\n", call Confirmed.size());
      }
    }
    
    }
*/
// New Dijkstra shortest path algorithm from The Crazy Programmer
  void Dijkstra(){

    uint16_t nodesize[MAX];
    uint16_t size = call RouteTable.size();
    uint16_t i,j,nexthop;
    uint16_t Cost[MAX][MAX];
    uint16_t dist[MAX],path[MAX], V[MAX];
    uint16_t num,mindist,next;

    uint16_t base = TOS_NODE_ID;
    bool G[MAX][MAX];

    LinkState nextnode;
    LinkState nextnode2;

    for(i = 0; i < MAX; i++) {
      for(j = 0; j < MAX; j++) {
        G[i][j] = FALSE;
      }
    }
    
    for(i = 0; i < size; i++) {
      nextnode = call RouteTable.get(i);
      for(j = 0; j < nextnode.arrLength; j++){
        G[nextnode.node][nextnode.neighbors[j]] = TRUE;
      }
    }

    for(i = 0; i < MAX; i++){
      for(j = 0; j < MAX; j++){
        if(G[i][j] == FALSE){
          Cost[i][j] = INFINITY;
        }
        else {
          Cost[i][j] = 1;//G[i][j]
        }
      }
    }

    //initialize dist[], path[], and Visited node
    for(i = 0; i < MAX; i++) {
      dist[i] = Cost[base][i];
      path[i] = base;
      V[i] = 0;
    }
    
    dist[base] = 0;
    V[base] = 1;
    num = 1;

    while(num < MAX - 1){
      mindist = INFINITY;
      //nextnode gives the node at minimum distance
      for(i = 0; i < MAX; i++){
        if(dist[i] <= mindist && V[i] == 0){
          mindist = dist[i];
          next = i;
        }
      }

      //check if a better path exits through nextnode
      V[next] = 1;

      for(i = 0; i < MAX; i++) {
        if(V[i] == 0) {
          if(mindist + Cost[next][i] < dist[i]) {
            dist[i] = mindist + Cost[next][i];
            path[i] = next;
          }
        }
      }
      num++;
    }

    //path and distance of each node
    for(i = 0; i < MAX; i++){
      nexthop = TOS_NODE_ID;
      if(dist[i] != INFINITY){
        if(i != base) {
          j = i;

          do {
            if(j != base){
              nexthop = j;
            }
            j = path[j];
          } while(j != base);
        }

        else {
          nexthop = base;
        }

        if(nexthop != 0){
          call tableroute.insert(i, nexthop);
        }
      }
    }

    // Transfer to confirmed list
    if(call Confirmed.isEmpty()){
      for(i = 1; i <= 10; i++){
        nextnode2.node = i;
        nextnode2.cost = Cost[base][i];
        nextnode2.nextHop = call tableroute.get(i);
        call Confirmed.pushfront(nextnode2);
      }
    } 
  }
  



} // END END


    



