/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require validation';

return baseclass.extend({
	stubValidator: {
		factory: validation,
		apply(type, value, args) {
			if (value != null)
				this.value = value;

			return validation.types[type].apply(this, args);
		},
		assert(condition) {
			return !!condition;
		}
	}
});
