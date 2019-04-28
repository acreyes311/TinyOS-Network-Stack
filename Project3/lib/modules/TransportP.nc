#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/channels.h"
#include "../../includes/sendInfo.h"

/**
 * The Transport interface handles sockets and is a layer of abstraction
 * above TCP. This will be used by the application layer to set up TCP
 * packets. Internally the system will be handling syn/ack/data/fin
 * Transport packets.
 *
 * @project
 *   Transmission Control Protocol
 * @author
 *      Alex Beltran - abeltran2@ucmerced.edu
 * @date
 *   2013/11/12
 */

 /*
// State of a socket. 
typedef struct socket_store_t{
    uint8_t flag;
    enum socket_state state;
    socket_port_t src;
    socket_addr_t dest;
    socket_t fd;

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

*/

module TransportP{
    provides interface Transport;

    uses interface SimpleSend as Sender;    
    uses interface List<socket_store_t> as SocketList;
    uses interface List<LinkState> as ConfirmedList;
    uses interface List<socket_store_t> as socketTemp;

}


implementation {
    



    //get function
    command socket_store_t Transport.getSocket(socket_t fd) {
        socket_store_t temp;
        uint16_t i;
        uint16_t size = call SocketList.size();

        for(i = 0; i < size;i++) {
            temp = call SocketList.get(i);
            if(fd == temp.fd){
                return temp;
            }
        }

    }// End getSocket

    
    command error_t Transport.setSocket(socket_t fd, socket_store_t sck){
        socket_store_t temp;
        uint16_t i;
        //bool found;

        for (i = 0; i < call SocketList.size();i++){
            temp = call SocketList.get(i);
            if(fd  == temp.fd){
                temp = call SocketList.remove(i);
                call SocketList.pushback(sck);
                return SUCCESS;
            }
        }
        //else
        return FAIL;
    }// End setSocket

   /**
    * Get a socket if there is one available.
    * @Side Client/Server
    * @return
    *    socket_t - return a socket file descriptor which is a number
    *    associated with a socket. If you are unable to allocated
    *    a socket then return a NULL socket_t.
    */
   command socket_t Transport.socket(){
    socket_t fd;    // fd ID
    socket_store_t newSocket;  // socket
    int i;

    if(call SocketList.size() < MAX_NUM_OF_SOCKETS) { // < 10
        // Gets the FD id of last index in list
        newSocket.fd = call SocketList.size();
        fd = call SocketList.size();

        //Initialize socket with default values
        newSocket.state = CLOSED;
        newSocket.lastWritten = 0;
        newSocket.lastAck = 0;
        newSocket.lastSent = 0;
        newSocket.lastRead = 0;
        newSocket.lastRcvd = 0;
        newSocket.nextExpected = 0;
        newSocket.RTT = 0;
        newSocket.effectiveWindow = SOCKET_BUFFER_SIZE; // 128

        //Push into socket list
        for(i = 0; i < SOCKET_BUFFER_SIZE; i++){
            newSocket.rcvdBuff[i] = 255;
            newSocket.sendBuff[i] = 255;
        }
        call SocketList.pushback(newSocket);

        dbg(TRANSPORT_CHANNEL, "Socket %d Allocated.\n",newSocket.fd);

        return newSocket.fd;   // Returns the fd id
    }

    else {
        dbg(TRANSPORT_CHANNEL, "No socket allocated. Returning NULL.\n");
        return NULL;
    }
   }// END socket()


   /**
    * Bind a socket with an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       you are binding.
    * @param
    *    socket_addr_t *addr: the source port and source address that
    *       you are biding to the socket, fd.
    * @Side Client/Server
    * @return error_t - SUCCESS if you were able to bind this socket, FAIL
    *       if you were unable to bind.
    */
   command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
    socket_store_t tempSocket;
    uint16_t i;

    //Loop through Socket List and find socket fd to bind
    for (i = 0; i < call SocketList.size(); i++) {
        tempSocket = call SocketList.get(i);

        if(fd == tempSocket.fd) {
            //Get Socket from list. Modify. And re-insert
            tempSocket = call SocketList.remove(i);

            //socket_port_t src; / socket_addr_t dest;
            tempSocket.src = addr->port;
            tempSocket.dest = *addr; // dest is socket_addr_t so assign all addr

            call SocketList.pushback (tempSocket);

            dbg(TRANSPORT_CHANNEL, "Socket Bind Successful.\n");

            return SUCCESS;
        }
    }
    // Otherwise return FAIL
    dbg(TRANSPORT_CHANNEL, "Failed bind.\n");
    return FAIL;
   } // END OF BIND


   /**
    * Checks to see if there are socket connections to connect to and
    * if there is one, connect to it.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting an accept. remember, only do on listen. 
    * @side Server
    * @return socket_t - returns a new socket if the connection is
    *    accepted. this socket is a copy of the server socket but with
    *    a destination associated with the destination address and port.
    *    if not return a null socket.
    */
   command socket_t Transport.accept(socket_t fd) {
    socket_store_t temp;
    //bool flag;
    //socket_t tempfd;
    int i;
    // loop through list checking for matching fd and if Listening
    for(i = 0; i < call SocketList.size(); i++){
        temp = call SocketList.get(i);

        // Check if listening
        if(fd == temp.fd && temp.state == LISTEN) {

            dbg(TRANSPORT_CHANNEL, "Socket Accept Successfull.\n");
            return temp.fd;
        }
    }
    //Otherwise return NULL
    dbg(TRANSPORT_CHANNEL, "Socket %d accept failed. Returning NULL.\n", fd);
    return NULL;
   } // End accept


   /**
    * Write to the socket from a buffer. This data will eventually be
    * transmitted through your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a write.
    * @param
    *    uint8_t *buff: the buffer data that you are going to wrte from.
    * @param
    *    uint16_t bufflen: The amount of data that you are trying to
    *       submit.
    * @Side For your project, only client side. This could be both though.
    * @return uint16_t - return the amount of data you are able to write
    *    from the pass buffer. This may be shorter then bufflen
    */
    //Client Side:
    //Write Clients buffer content that was passed in sendBuff[SOCKET_BUFFER_SIZE]
    //Then make a packet an send ACKs for each time it receives data.
    //Asks client to send more data
    //Return how much data the server was able to read from buff, send from Client sendBuff(written to Servers rcvdBuff).

    /*
    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t temp;
        uint8_t buffInd, buffLimit, last,next;
        int i;
        uint16_t writeable = 0;
        LinkState ls;
        pack Data;
        bool found = FALSE;

        Data.src = TOS_NODE_ID;
        Data.protocol = PROTOCOL_TCP;

        while(!call SocketList.isEmpty()){
            temp = call SocketList.popfront();

            //find socket and write to server send buffer
            if(temp.fd == fd && !found){
               // call SocketList.popfront(); // Again?

                if(bufflen > (SOCKET_BUFFER_SIZE - temp.lastWritten)){
                    buffInd = SOCKET_BUFFER_SIZE - temp.lastWritten;
                }   // End if
                else
                buffInd = bufflen;

                last = temp.lastSent;

                //Write data from buff into received buff. Starting from temp lastwritten
                for(i = 0; i < (temp.lastWritten + buffInd); i++){
                    temp.sendBuff[i] = last;
                    writeable++;
                    last++;
                } // End for

                // Update temp socket
                temp.lastWritten = i;
                temp.lastSent = last;
                temp.flag = 4;

                // Make data packet
                Data.TTL = MAX_TTL;
                Data.seq = i;
                Data.dest = temp.dest.addr;
                memcpy(Data.payload, &temp,(uint8_t)sizeof(temp));

                for(i = 0; i < call ConfirmedList.size(); i++){
                    ls = call ConfirmedList.get(i);
                    if(ls.node == Data.dest){
                        next = ls.nextHop;
                        break;
                    }//end if
                }// end for

                temp.lastWritten = 0;

                found = TRUE;

                call SocketList.pushback(temp);
                call Sender.send(Data,next);
                return writeable;
            }
            //return writeable;
        }
    }
*/

    
   command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
    socket_store_t temp;
    int i,j,lw;
    int avail;
    uint16_t nextHop;
    LinkState ls;

    // will write to this packet
    pack Data;

    //Iterate through list and find appropriate fd
    for(i = 0; i < call SocketList.size(); i++){
        temp = call SocketList.get(i);

        if(fd == temp.fd){
            temp = call SocketList.remove(i);

            //start at last Written part of buffer
            lw = temp.lastWritten + 1;

            // calculate spae
            avail = SOCKET_BUFFER_SIZE - lw;

            dbg(TRANSPORT_CHANNEL,"Node %d writing on socket.\n",TOS_NODE_ID);

            //Write to buffer
            for(j = 0; j < bufflen; j++){
                temp.sendBuff[lw] = buff[j];
                lw++;
                avail--;

                //if no more available space break
                if(avail == 0)
                    break;

            }// End inner for J

            temp.lastWritten = lw;
            temp.flag = 4;

            dbg(TRANSPORT_CHANNEL, "Data written on Socket %d\n",fd);

            //Initialize DATA packet
            Data.src = TOS_NODE_ID;
            Data.dest = temp.dest.addr;
            Data.protocol = PROTOCOL_TCP;
            Data.TTL = MAX_TTL;

            // copy temp into Data packet payload
            memcpy(Data.payload, &temp, (uint8_t)sizeof(temp));
            //dbg(TRANSPORT_CHANNEL,"MEMCOPIED WRITE\n");
    
            //Get next hop
            for(j = 0; j < call ConfirmedList.size(); j++){
                ls = call ConfirmedList.get(j);
                if(ls.node == Data.dest) 
                    nextHop = ls.nextHop;
            } // End net hop For loop

            dbg(TRANSPORT_CHANNEL, "Data pack sent out Node %d.\n", Data.dest);

            //Send Pack
            call Sender.send(Data,nextHop);
            //call Sender.send(Data,1);

            //Reinsert socket back in SocketList
            call SocketList.pushback(temp);

            //Return amount able to write on buffer
            return j;
        }// End If fd check
    }// End for loop that iterates through list

    return 0;   // Failed to write
    
   } // End of WRITE()
  

   /**
    * This will pass the packet so you can handle it internally. 
    * @param
    *    pack *package: the TCP packet that you are handling.
    * @Side Client/Server 
    * @return uint16_t - return SUCCESS if you are able to handle this
    *    packet or FAIL if there are errors.
    */
   command error_t Transport.receive(pack* package) {
    //Handled in Node.nc

   }

   /**
    * Read from the socket and write this data to the buffer. This data
    * is obtained from your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a read.
    * @param
    *    uint8_t *buff: the buffer that is being written.
    * @param
    *    uint16_t bufflen: the amount of data that can be written to the
    *       buffer.
    * @Side For your project, only server side. This could be both though.
    * @return uint16_t - return the amount of data you are able to read
    *    from the pass buffer. This may be shorter then bufflen
    */

    // Server Side:
    // Want to write to Clients buffer with data passed in to servers rcvdBuff[SOCKET_BUFFER_SIZE]
    // Then make packet andd send ACKs for each time it receives data.
    // Ask client to send more data
    // Return how much data the server was able to read from buffsent from Client sendBuff(written to Servers rcvdBuff)

   command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
    socket_store_t temp, transferSocket;
    uint8_t buffInd,lastReceived,i;
    uint16_t read,write,index;
    bool found = FALSE;

    for(i = 0; i < call SocketList.size();i++){
        temp = call SocketList.get(i);

        if(temp.fd == fd && found == FALSE){
            index = i;
            found = TRUE;
        }//end if
    }//end for
    //dbg(TRANSPORT_CHANNEL,"AFTER FIRST FOR LOOP IN READ________\n");
    if(found == FALSE){
        dbg(TRANSPORT_CHANNEL,"INSIDE READ: NOT FOUND RETURN 0\n");
        return 0;
    }
    else{
        temp = call SocketList.get(index);
        
        //Check if size of buffer(data plan to write) is larger than sockets effective window
        // if(bufflen > temp.effectiveWindow){ // FOR SOME REASON effectiveWindow = 0. Should be 128 set in socket()
        //    read = temp.effectiveWindow;
        // }
        //else sart with sockets next expected
        //else{
        read = bufflen;
        // dbg(TRANSPORT_CHANNEL," NOW READ ============== %d\n",read);
        // }
        lastReceived = temp.nextExpected;

        // move into received buffer
        for(i = 0; i < read; i++){
            temp.rcvdBuff[lastReceived] = lastReceived + temp.lastRcvd;//buff[i];
            lastReceived++;
            write++;
            //dbg(TRANSPORT_CHANNEL,"FORLOOP___rcvdBuff:%d, lastReceived:%d, write:%d, i:%d\n",temp.rcvdBuff[lastReceived],lastReceived,write,i);
            //decrease window
            if(temp.effectiveWindow > 0)
                temp.effectiveWindow--;

        }// end for

        //Update socket about last data received and last data written onto buffer
        temp.lastRcvd = i;
        temp.rcvdBuff[lastReceived] = 255;

        //Check for effective window
        if(temp.effectiveWindow == 0)
            temp.nextExpected = 0;
        // Else still have room     
        else
            temp.nextExpected = lastReceived + 1;

        //read = 0;
        dbg(TRANSPORT_CHANNEL,"---READING DATA ----\n");  
        //PRINT OUT DATA
        for(i = 0; i < temp.lastRcvd; i++){
            if(temp.rcvdBuff[i] != 255 && temp.rcvdBuff[i] != 0){
                dbg(TRANSPORT_CHANNEL,"Read index:[%d]: %d \n",i,temp.rcvdBuff[i]);
                temp.rcvdBuff[i] = 255;
                temp.effectiveWindow++;
                read++;
            }//end if            
        }//end print for

        // Write done now puch into temp then socketlist
        while(!call SocketList.isEmpty()){
            transferSocket = call SocketList.front();
            if(temp.fd != transferSocket.fd){
                call socketTemp.pushfront(call SocketList.front());                
            }
            else
                call socketTemp.pushfront(temp);
            call SocketList.popfront();    
        }//end !while

        while(!call socketTemp.isEmpty()){
            call SocketList.pushfront(call socketTemp.front());
            call socketTemp.popfront();
        }//end 2nd while

        return read;
    }
   }

   /* 
   command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        // *JF
    int i,j,len;
    int avail;  // space remaining
    socket_store_t temp;


    dbg(TRANSPORT_CHANNEL,"In Transport.read().\n");

    //go through list and fid appropriate fd
    for(i = 0; i < call SocketList.size(); i++){
        temp = call SocketList.get(i);

        if(fd == temp.fd){
            temp = call SocketList.remove(i);

            // Start at last written 
            len = temp.lastRead + 1;

            avail = SOCKET_BUFFER_SIZE - len;

            for(j = 0; j < bufflen; j++){

                temp.sendBuff[len] = buff[j];
                len++;
                avail--;

                // If no more spave available stop reading.
                if(avail == 0)
                    break;
            }// end inner for j

            temp.lastRead = len;

            // Insert back into SocketList
            call SocketList.pushback(temp);

            dbg(TRANSPORT_CHANNEL,"Data read to socket %d\n",fd);

            // This amount of data read
            return j;
        }
    }
    return 0;   // Failed

   } // End of READ
*/

   /**
    * Attempts a connection to an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are attempting a connection with. 
    * @param
    *    socket_addr_t *addr: the destination address and port where
    *       you will atempt a connection.
    * @side Client
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a connection with the fd passed, else return FAIL.
    */
    // Make socket_store_t truct and update with SYN, dest port and dest addr.
    // Struct is now payload to be added to a packet with src TOS_NODE_ID, dest: addr->addr
    // Iterate through route table to find next node.
   command error_t Transport.connect(socket_t fd, socket_addr_t * addr) {

    socket_store_t temp,temp2;
    pack SYN;
    LinkState lsdest;
    uint16_t nh,i;
    bool flag;

    // Fill in SYN packet
    SYN.src = TOS_NODE_ID;
    SYN.dest = addr->addr;
    SYN.seq = 1; 
    SYN.TTL = MAX_TTL;
    SYN.protocol = PROTOCOL_TCP;

    //temp = call SocketList.get(fd);
    temp.dest.port = addr->port;
    temp.dest.addr = addr->addr;
    temp.flag = 1;


    // update info in list
    while(!call SocketList.isEmpty()){
        temp2 = call SocketList.front();
        if(temp.fd == temp2.fd){
            call socketTemp.pushfront(temp);
        }
        else{
            call socketTemp.pushfront(temp2);
        }
        call SocketList.popfront();
    }
    while(!call socketTemp.isEmpty()){
        call SocketList.pushfront(call socketTemp.front());
        call socketTemp.popfront();
    }
    //memcpy(dest,src,size)
    memcpy(SYN.payload, &temp, (uint8_t)sizeof(temp));

    dbg(GENERAL_CHANNEL, "Transport.connect().\n");

    // Find the next hop for destination node
    for(i = 0; i < call ConfirmedList.size(); i++) {
        lsdest = call ConfirmedList.get(i);
        if(SYN.dest == lsdest.node)
            nh = lsdest.nextHop;
            flag = TRUE;
    }
    dbg(TRANSPORT_CHANNEL, "SYN packet being sent to nextHop %d, intended for Node %d.\n",nh,addr->addr);
    call Sender.send(SYN,nh);
    if(flag == TRUE)
        return SUCCESS;
    else
        return FAIL;

   }

   /**
    * Closes the socket.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are closing. 
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
   command error_t Transport.close(socket_t fd) {
    socket_store_t temp;
    int i;

    //Search list for Socket fd
    for(i = 0; i < call SocketList.size(); i++){
        temp = call SocketList.get(i);

        if(fd == temp.fd) {
            temp = call SocketList.remove(i);
            temp.state = CLOSED;
            call SocketList.pushback(temp);
            dbg(TRANSPORT_CHANNEL,"Socket %d is now CLOSED.\n",fd);

            return SUCCESS;
        }
    }
    return FAIL;

   }// End Close

   /**
    * A hard close, which is not graceful. This portion is optional.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing. 
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
   command error_t Transport.release(socket_t fd) {

   }

   /**
    * Listen to the socket and wait for a connection.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing. 
    * @side Server
    * @return error_t - returns SUCCESS if you are able change the state 
    *   to listen else FAIL.
    */
   command error_t Transport.listen(socket_t fd) {
    socket_store_t temp;
    int i;

    for(i = 0; i < call SocketList.size(); i++) {
        temp = call SocketList.get(i);

        if(temp.fd == fd) {
            temp = call SocketList.remove(i);
            temp.state = LISTEN;
            call SocketList.pushback(temp);

            dbg(TRANSPORT_CHANNEL, "Socket %d has been set to listen.\n", fd);

            return SUCCESS;
        }
    }
    return FAIL;
   }// End listen

}// end implement
