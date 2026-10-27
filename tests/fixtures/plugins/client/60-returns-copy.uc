'use strict';

/* works on a copy and returns it; a null value is dropped from the output */
return {
	client: function(config) {
		const copy = json(sprintf('%J', config));
		copy.log.level = 'debug';
		copy.log.timestamp = null;
		return copy;
	}
};
