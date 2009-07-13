// These are the Javascript functions the jQGrid widget relies on

var jqgw_debug = 0;

// activateTitleBar on a table will make clicking on the caption the same as click on the collapse icon.
// It also adds a second click handler to the collapse icon in order to expand/collapse the edit panel as well.
function activateTitleBar(table) {
	var v = jQuery(table).closest('.ui-jqgrid-view');
	v.find('.ui-jqgrid-titlebar').click(function() {
		jQuery(this).find('.ui-jqgrid-titlebar-close').trigger('click');
		});
	v.find('.ui-jqgrid-titlebar-close').click(function() {
    	if (jQuery(table).getGridParam('gridstate') == 'visible') {
    		v.find('.jqgw-form').slideDown('normal');
    	} else {
    		v.find('.jqgw-form').slideUp('normal');
    	}
	});
}
// The hideTable and openTable functions provide a way to "click on the collapse icon" programmatically.
function hideTable(table) {
	if (jQuery(table).getGridParam('gridstate') == 'visible') {
		jQuery(table).closest('.ui-jqgrid-view').find('.ui-jqgrid-titlebar-close').trigger('click');
	}
}
function openTable(table) {
	if (jQuery(table).getGridParam('gridstate') == 'hidden') {
		jQuery(table).closest('.ui-jqgrid-view').find('.ui-jqgrid-titlebar-close').trigger('click');
	}
}

// The following functions implement a pre-cache for JSON requests, which allow for
// the parent widget to send data updates for itself and all children at once to minimize
// AJAX requests.  It is hooked into jQGrid as a function datatype, with an option like this:
// datatype: function(pdata) { retrieveJSON('table_id_selector','url/to/retrieve',pdata); }
// Cached data will be passed back, or, if there is nothing cached, then data is requested.
var pendingJSON = new Array();
function retrieveJSON(table,purl,pdata) {
	var ts = jQuery(table)[0],
	loadComplete = jQuery.isFunction(ts.p.loadComplete) ? ts.p.loadComplete : false;
	if (pendingJSON[table] == null) {
		indicateReq(table);
		jQuery.getScript(purl+'&'+jQuery.param(pdata));
	} else {
		ts.addJSONData(eval("("+pendingJSON[table]+")"));
		if(loadComplete) loadComplete(pendingJSON[table],'success');
		delete pendingJSON[table];
	}
}
function pushJSON(table,json) {
  pendingJSON[table] = json;
}
// jQGrid's "loading" UI behavior is hidden away as a private function, so I duplicated
// the basic essence of its beginReq() function here.  It is used to send the UI for child
// tables into the "loading" state while the parent loads. The table is expanded when this
// happens, in order for the "loading..." message to appear in a sensible place.
// I also ditched the beforeRequest and the check for initial collapsed status.
function indicateReq(table) {
  var ts = jQuery(table)[0];
	//openTable(table);
	switch(ts.p.loadui) {
		case "disable":
			break;
		case "enable":
			jQuery("#load_"+ts.p.id).show();
			break;
		case "block":
			jQuery("#lui_"+ts.p.id).show();
			jQuery("#load_"+ts.p.id).show();
			break;
	}
}
// This opens an edit panel under the row whose row/cell was clicked on.
// The openRowPanel function is designed to be a callback for jQGrid's onCellSelect event.
function openRowPanel(rowid,cellindex,html,target,url,panels) {
	if(cellindex == 'row' || panels.length == 0 || panels[cellindex] == 1) {
		var t = jQuery(target).closest('.ui-jqgrid-btable'),
		v = jQuery(target).closest('.ui-jqgrid-view'),
		//w = v.width,
		w = t.css('width'),
		id = t.attr('id'),
		r = t.find('#' + rowid),
		exep_dom = v.find('.jqgw-form'),
		exep = (exep_dom.length > 0),
		pid = id + '_panel' + rowid + '_' + cellindex;
		// unfocus anything already focused, then focus the cell that was clicked on
		// might be better to use .ui-state-focus, but it wasn't very visible
		if (cellindex != 'row') {
			var c = r.find('td:eq(' + cellindex + ')');
			t.find('.fancytable_cell_focus').removeClass('fancytable_cell_focus');
			c.addClass('fancytable_cell_focus');
		}
		// if there are any panels open already, tell them to close
		//t.find('.open_edit_panel').removeClass('open_edit_panel').addClass('closing_edit_panel');
		// add the panel
		// for some reason I need to explicitly set the widths
		//var w = t.css('width');
		//var row_content = '<tbody id="tbody_' + pid + '" style="display:none;width:' + w + ';">' + '<tr style="">' + '<td id="td_' + pid + '" style="width:' + w + ';" colspan="8">' + 'Loading editing panel...' + '</td></tr></tbody>';
		//r.after(row_content);
		var ntb = document.createElement('tbody'),
		jqntb = jQuery(ntb).addClass('jqgw-form').hide().width(w).
			css('height','auto').attr('id','tbody_'+pid).insertAfter(r),
		nr = document.createElement('tr'),
		jqr = jQuery(nr).width(w).appendTo(jqntb),
		ntd = document.createElement('td'),
		jqntd = jQuery(ntd).width(w).attr('colspan', r.attr('cells').length).html('Loading edit panel...').appendTo(jqr).load(url,
		//t.find('#td_' + panelId).load(url,
			{'id': rowid, 'table': id, 'panel': cellindex, 'authenticity_token': rails_authenticity_token},
			function(data) { 
				if(exep) exep_dom.slideUp('normal', function() { jQuery(this).remove();});
				jQuery(ntb).slideDown('normal');
				//t.find('.closing_edit_panel').slideUp('normal', function() { jQuery(this).remove();});
				//pi.css({'display':'block'});
				//po.addClass('open_edit_panel').slideDown('normal');
			},'script');
	}
}

// This opens an edit panel under the title/toolbar
// The openTitlePanel function is designed to be the callback for jQGrid's onSelectRow or onCellSelect events.
// Firebug will sometimes announce an error if you happen to mouseover the edit panel div.
// After much fiddling with this, I have concluded that this is actually a bug in Firebug, and not this.
function openTitlePanel(rowid,cellindex,html,target,url,panels) {
	if(cellindex == 'row' || panels.length == 0 || panels[cellindex] == 1) {
		var t = jQuery(target).closest('.ui-jqgrid-btable'),
		v = jQuery(target).closest('.ui-jqgrid-view'),
		id = t.attr('id'),
		w = v.css('width'),
		//w = v.width,
		nd = document.createElement('div'),
		hd = v.find('.ui-jqgrid-hdiv'),
		exep_dom = v.find('.jqgw-form'),
		exep = (exep_dom.length > 0),
		ep_id = 'ep_'+id,
		jqnd = jQuery(nd).addClass('jqgw-form').hide().width(w).
			css('height','auto').attr('id','incoming_edit_panel').insertBefore(hd);
		jqnd.load(url,
			{'id': rowid, 'table': id, 'panel': cellindex, 'authenticity_token': rails_authenticity_token},
			function(data) {
				if(exep) exep_dom.slideUp('normal', function() { jQuery(this).remove();});
				//if(exep) exep_dom.slideUp('fast');
				jqnd.slideDown('normal', function() {
					//if(exep) exep_dom.remove();
					jqnd.attr('id', ep_id);
				});
			});		
	}
}

// This closes an edit panel in the title/toolbar area (in response to submit or cancel)
function closeEditPanel(table) {
	jQuery(table).closest('.ui-jqgrid-view').find('.jqgw-form').slideUp('normal', function () {
		if(jqgw_debug > 1) console.log('closeEditPanel: slide up complete. About to remove myself.');
		jQuery(this).remove();
	});
}
