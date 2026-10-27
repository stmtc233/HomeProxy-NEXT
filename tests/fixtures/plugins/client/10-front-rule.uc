'use strict';

/* goes in front of the built-in rules; the domain also proves ctx arrives */
return {
	client: function(config, ctx) {
		unshift(config.route.rules, {
			domain_suffix: [ 'plugin.example', `${ctx.routing_mode}.${ctx.proxy_mode}.${ctx.ipv6_support}.ctx.example` ],
			action: 'route',
			outbound: 'direct-out'
		});
	}
};
