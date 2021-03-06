#include "../includes/am_types.h"

configuration TransportC {
	provides interface Transport;
	uses interface List<LinkState> as ConfirmedC;
}

implementation {
	components TransportP;
	Transport = TransportP;

	components new SimpleSendC(AM_PACK);
	TransportP.Sender -> SimpleSendC;

	// Our list of sockets
	components new ListC(socket_store_t, 10) as SocketListC;
	TransportP.SocketList -> SocketListC;

	TransportP.ConfirmedList = ConfirmedC;

	components new ListC(socket_store_t,10) as socketTempC;
	TransportP.socketTemp -> socketTempC;

}