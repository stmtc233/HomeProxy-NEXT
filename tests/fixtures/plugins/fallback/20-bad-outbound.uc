'use strict';

/* sing-box check rejects this: the whole plugin set must be dropped */
return {
	client: function(config) {
		push(config.outbounds, { type: 'no-such-type', tag: 'bad-out' });
	}
};
