Ext.define('app.store.HoursReport', {
	extend: 'Ext.data.TreeStore',

	requires: [
		'app.model.HoursReport'
	],

	constructor: function(cfg) {
		var me = this;
		cfg = cfg || {};
		me.callParent([Ext.apply({
			model: 'app.model.HoursReport',
			storeId: 'HoursReport',
			proxy: {
				type: 'ajax',
				url: '/intranet-reporting/json/HoursReport',
				reader: {
					type: 'json'
				}
			}
		}, cfg)]);
	}
});
