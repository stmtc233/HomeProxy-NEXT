'use strict';

/* fails halfway: its first change must be rolled back */
return {
	client: function(config) {
		config.route.final = 'rolled-back';
		die('plugin gave up');
	}
};
