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

    components new TimerMilliC() as myTimerC;   // create a new timer named myTimerC
    components new ListC(Neighbor* , 100) as List;
    components new ListC(pack, 100) as List_V2;
    
    //App.Boot -> MainC.boot
    //App.periodicTimer -> myTimerC;    //Wire interface to component
    Node.periodicTimer -> myTimerC;    //Wire interface to component
    
    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    Node.Neighbors -> List;
    Node.Packets -> List_V2;
    
    components new ListC(Neighbor*, 100) as DroppedNeighborsC;
    Node.DroppedNeighbors -> DroppedNeighborsC;
    // Add component Lists ( packetlist, neighborlists)

}
