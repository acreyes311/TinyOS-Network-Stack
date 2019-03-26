#include "../../packet.h"
#include "../../includes/socket.h"

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

    uses interface List<socket_store_t> as SocketList;

}


implementation {
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
    socket_store_t tempSocket;  // socket

    if(call SocketList.size() < MAX_NUM_SOCKETS) { // < 10
        // Gets the FD id of last index in list
        tempSocket.fd = call SocketList.size();
        fd = call SocketList.size();

        //Initialize socket with default values
        tempSocket.socket_state = CLOSED;
        tempSocket.lastWritten = 0;
        tempSocket.lastAck = 0;
        tempSocket.lastSent = 0;
        tempSocket.lastRead = 0;
        tempSocket.lastRcvd = 0;
        tempSocket.nextExpected = 0;
        tempSocket.RTT = 0;
        tempSocket.effectiveWindow = SOCKET_BUFFER_SIZE; // 128

        //Push into socket list
        call SocketList.pushback(tempSocket);

        dbg(TRANSPORT_CHANNEL, "Got Socket.\n");

        return tempSocket.fd;   // Returns the fd id
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
    int i;

    //Loop through Socket List and find socket fd to bind
    for (i = 0; i < call SocketList.size();i++) {
        tempSocket = call SocketList.get.(i);

        if(fd == tempSocket.fd) {
            //Get Socket from list. Modify. And re-insert
            tempSocket = call SocketList.remove(i);

            //socket_port_t src; / socket_addr_t dest;
            tempSocket.src = addr->port;
            tempSocket.dest = *addr; // dest is socket_addr_t so assign all addr

            call SocketList.pushback (tempSocket);

            dbg(TRANSPORT_CHANNEL, "Socket Bind Successfull./n");

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
        tempSocket = call SocketList.get(i);
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
   command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {

   }

   /**
    * This will pass the packet so you can handle it internally. 
    * @param
    *    pack *package: the TCP packet that you are handling.
    * @Side Client/Server 
    * @return uint16_t - return SUCCESS if you are able to handle this
    *    packet or FAIL if there are errors.
    */
   command error_t Transport.receive(pack* package) {

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
   command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {

   }

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
   command error_t Transport.connect(socket_t fd, socket_addr_t * addr) {

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

   }

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
    
   }
}
