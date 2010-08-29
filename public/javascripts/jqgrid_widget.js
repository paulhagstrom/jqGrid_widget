// These are the Javascript functions the jQGrid widget relies on

var jqgw_debug = 0;

// Functions to supplement jQGrid:

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
		jQuery(table).setGridState('hidden');
//		jQuery(table).closest('.ui-jqgrid-view').find('.ui-jqgrid-titlebar-close').trigger('click');
	}
}
function openTable(table) {
	if (jQuery(table).getGridParam('gridstate') == 'hidden') {
		jQuery(table).setGridState('visible');
//		jQuery(table).closest('.ui-jqgrid-view').find('.ui-jqgrid-titlebar-close').trigger('click');
	}
}
// jQGrid's "loading" UI behavior is hidden away as a private function, so I duplicated
// the basic essence of its beginReq() function here.  It is used to send the UI for child
// tables into the "loading" state while the parent loads. The table is expanded when this
// happens, in order for the "loading..." message to appear in a sensible place.
// I also ditched the beforeRequest and the check for initial collapsed status.
function indicateReq(table) {
  var ts = jQuery(table)[0];
	//openTable(table);
	if(ts){
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
}

// Dataset caching:

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

// JqgridWidget functions:

// create the "specs" argument
function clickSpecsData(rowid,cellindex,target) {
	var id = jQuery(target).closest('.ui-jqgrid-btable').attr('id');
	vid = jQuery(target).closest('.ui-jqgrid-view').attr('id');
	return {'id': rowid, 'table': id, 'cell_column': cellindex, 'table_view': vid, 'authenticity_token': rails_authenticity_token};
}

// make sure an edit panel is open in the titlebar area
// used by the selector click function to open up a new record.
function ensureTitlePanel(target,url) {
	openTitlePanel(clickSpecsData('0','row',target),url,false);
}

// opens an edit panel in the titlebar area
// see clickAction and clickSpecsData for target and specs
// if reopen is false, then it will do nothing if one is already open.
// if reopen is true, it'll destroy an existing panel and replace it with a new one.
// Note: newer jQuery slideDown does not work properly afaict, so I animate the height.
//function openTitlePanel(target, specs, url, reopen) {
function openTitlePanel(specs, url, reopen) {
	var id = specs['table'],
	t = jQuery('#' + id),
	// v = jQuery(target).closest('.ui-jqgrid-view'),
	vid = specs['table_view'],
	v = jQuery('#' + vid),
	xpans = v.find('.jqgw-form');
	if(reopen || xpans.length == 0) {
		nd = document.createElement('div'),
		w = v.css('width'),
		hd = v.find('.ui-jqgrid-hdiv'),
		pid = 'panel_'+id,
		jqnd = jQuery(nd).addClass('jqgw-form').hide().width(w).
			css('height','auto').attr('id','incoming_edit_panel').insertBefore(hd);
		jqnd.load(url, specs, function(data) {
				/* if(xpans.length > 0) xpans.slideUp('normal', function() { jQuery(this).remove();}); */
				jqnd.animate({height:'show'}, 'fast', '', function() {jqnd.attr('id',pid);});
				if(xpans.length > 0) xpans.animate({height:'hide'}, 'fast', '', function() { jQuery(this).remove();});
				/*jqnd.slideDown('normal', function() {
					jqnd.attr('id', pid);
				}); */
			});
	}
}

// opens an edit panel under the selected row
// see clickAction and clickSpecsData for target and specs
// if do_focus is true then it will focus the selected cell and unfocus everything else (only for cell clicks)
// Note: newer jQuery slideDown does not work properly afaict, so I animate the height.
// TODO: It would be nicer if the slideUp and slideDown went at the same time.
// function openRowPanel(target, specs, url, do_focus) {
function openRowPanel(specs, url, do_focus) {
	var id = specs['table'],
	cellindex = specs['cellindex'],
	rowid = specs['id'],
	t = jQuery('#' + id),
	// v = jQuery(target).closest('.ui-jqgrid-view'),
	vid = specs['table_view'],
	v = jQuery('#' + vid),
	xpans = v.find('.jqgw-form'),
	r = t.find('#' + rowid),
	w = t.css('width'),
	pid = id + '_panel' + rowid + '_' + cellindex;
	// unfocus anything already focused, then focus the cell that was clicked on
	// It might be better to use .ui-state-focus, but it wasn't very visible
	if (do_focus) {
		t.find('.jqgw_cell_focus').removeClass('jqgw_cell_focus');
		var c = r.find('td:eq(' + cellindex + ')');
		c.addClass('jqgw_cell_focus');
	}
	// css('position','absolute').css('opacity','0.8') creates an interesting effect (like Mac sheet)
	var nr = document.createElement('tr'),
	jqr = jQuery(nr).width(w).addClass('jqgw-form').hide().css('height','auto').css('position','absolute').css('opacity','0.8').attr('id','tr_'+pid).insertBefore(r),
	ntd = document.createElement('td');
/*	var ntb = document.createElement('tbody'),
	jqntb = jQuery(ntb).addClass('jqgw-form').hide().width(w).
		css('height','auto').attr('id','tbody_'+pid).insertBefore(r),
	nr = document.createElement('tr'),
	jqr = jQuery(nr).width(w).appendTo(jqntb),
	ntd = document.createElement('td'); */
	var jqntd = jQuery(ntd).width(w).attr('colspan', r.attr('cells').length).html('Loading edit panel...').appendTo(jqr).load(url,
		specs, function(data) { 
			if(xpans.length > 0) xpans.animate({height:'hide'}, 'fast', '', function() { jQuery(this).remove();});
			/* if(xpans.length > 0) xpans.slideUp('normal', function() { jQuery(this).remove();}); */
			/* jQuery(jqntb).animate({height:'show'}, 'fast'); */
			jQuery(jqr).animate({height:'show'}, 'fast');
			/* jQuery(ntb).slideDown('normal'); */
		});
}

// This closes an edit panel (in response to submit or cancel)
// Note: newer jQuery slideUp does not work properly afaict, so I animate the height.
function closeEditPanel(table) {
	jQuery(table).closest('.ui-jqgrid-view').find('.jqgw-form').animate({height:'hide'}, 'fast', function () {
		jQuery(this).remove();
	});
/*	jQuery(table).closest('.ui-jqgrid-view').find('.jqgw-form').slideUp('normal', function () {
		jQuery(this).remove();
	}); */
}

// This supports the live search functionality
var searchTimeOutHandler;
function doLiveSearch(field,url,ev){
	// var elem = ev.target||ev.srcElement;
	if(searchTimeOutHandler)
		clearTimeout(searchTimeOutHandler)
	searchTimeOutHandler = setTimeout("gridReload('"+field+"','"+url+"');",450);
}
function gridReload(field,url){
	var fv = jQuery("#"+field).val();
	var fn = jQuery("#"+field).attr('name');
	jQuery.getScript(url+"&livesearch="+field+"@"+fn+"@"+escape(fv));
} 
