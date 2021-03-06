/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"
#include "includes/socket.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    components new TimerMilliC() as periodicTimerC;   // create a new timer named myTimerC
    components new ListC(pack,64) as PacketsC;
    
    components new TimerMilliC() as acceptTimerC; 
    components new TimerMilliC() as writtenTimerC; 

    Node.Packets -> PacketsC;
    
    
    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

   // Node.Neighbors -> List;
    //Node.Packets -> List_V2;
    
    components new ListC(Neighbor, 64) as DroppedNeighborsC;
    Node.DroppedNeighbors -> DroppedNeighborsC;

    components new ListC(Neighbor, 64) as NeighborsC;
    Node.Neighbors -> NeighborsC;

    components RandomC as Random; 
    Node.Random -> Random;

    Node.periodicTimer -> periodicTimerC;    //Wire interface to component
    
    // ----- PROJECT2 -------
   // components new ListC(LinkState,64) as TentativeC;
    //Node.Tentative -> TentativeC;

    components new ListC(LinkState,64) as ConfirmedC;
    Node.Confirmed -> ConfirmedC;

    components new ListC(LinkState,64) as RouteTableC;
    Node.RouteTable -> RouteTableC;

    components new ListC(LinkState,64) as routeTempC;
    Node.routeTemp -> routeTempC;

    components new HashmapC(int,64) as tablerouteC;
    Node.tableroute -> tablerouteC;

    //components new ListC(LinkState,64) as tempLSC;
    //Node.tempLS -> tempLSC;

    components new TimerMilliC() as lspTimerC;
    Node.lspTimer -> lspTimerC;

    // ---- Project 3 -----
    components TransportC;
    Node.Transport -> TransportC;
    
    Node.acceptTimer -> acceptTimerC; 
    Node.writtenTimer ->writtenTimerC; 

    components new ListC(socket_store_t, 10) as SocketlistC;
    Node.Socketlist -> SocketlistC;

    components new ListC(socket_store_t, 10) as modSocketsC;
    Node.modSockets -> modSocketsC;

    // Connect to Transport
    //components TransportC
    Node.Transport->TransportC;
    TransportC.ConfirmedC->ConfirmedC;

    components LocalTimeMilliC;
    Node.LocalTime -> LocalTimeMilliC;


}
