interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(uint16_t port);
   event void setTestClient(uint16_t dest, uint16_t srcPort, uint16_t destPort, uint16_t transfer);
   event void ClientClose(uint8_t clientAddr, uint8_t srcPort, uint8_t destPort, uint8_t dest);
   event void setAppServer();
   //event void setAppClient();
   event void setAppClient(char* username);
      //uint8_t client,  char* username);
   event void broadcastMessage(char* username);
   event void unicastMessage(char* username, char* msg);
   event void printUsers();
   


}
