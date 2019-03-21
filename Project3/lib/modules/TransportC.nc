#include "../includes/am_types.h"

configuration TransportC {
	provides interface Transport;
}

implementation {
	components TransportP;
	Transport = TransportP;

	components new SimpleSendC(AM_PACK);
	TransportP.Sender -> SimpleSendC;

}