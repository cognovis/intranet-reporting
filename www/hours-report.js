Ext.Loader.setConfig({
	enabled: true
});

Ext.application({
	appFolder: 'app',
	name: 'HoursReport',
	models: ['HoursReport'],
	stores: ['HoursReportStore'],
	views: ['HoursReportView'],
	launch: function() {
		Ext.create('Ext.container.Viewport', {
			title: 'title',
			layout: 'fit',
			items: [{
				title: 'HoursReport',
				xtype: 'TreeGrid'

			}]
		});
	}
});
