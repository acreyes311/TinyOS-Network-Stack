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

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    components new TimerMilliC() as periodicTimerC;   // create a new timer named myTimerC
    components new ListC(pack,64) as PacketsC;

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
    components new ListC(LinkState,64) as TentativeC;
    Node.Tentative -> TentativeC;

    components new ListC(LinkState,64) as ConfirmedC;
    Node.Confirmed -> ConfirmedC;

    components new ListC(LinkState,64) as RouteTableC;
    Node.RouteTable -> RouteTableC;

    components new ListC(LinkState,64) as routeTempC;
    Node.routeTemp -> routeTempC;

    components new ListC(LinkState,64) as tempLSC;
    Node.tempLS -> tempLSC;

    components new HashmapC(int, 64) as tablerouteC;
    Node.tableroute -> tablerouteC;

    components new TimerMilliC() as lspTimerC;
    Node.lspTimer -> lspTimerC;

}
