$.fn.setupTree = function() {
  return $(this).each(function(){
    var tree = $(this);

    if (tree.hasClass('grouped')) {
      tree.css('margin-left', '45px');
    }

    tree.treeview({
      collapsed: true,
      animated: 'fast',
      prerendered: false,
      toggle: function(){
        var $this = $(this);
        if ($this.hasClass('loaded'))
          return;

        $this.addClass('loaded');
        var sublist = $this.find('>ul');
        var url = sublist.attr('url') || '/test';

        $.ajax({
          url: url,
          success: function(data) {
            sublist.animate({height: '0'}, 'fast', function(){
              sublist.remove();
              var newlist = $(data);
              newlist.css('display','none').appendTo($this);
              tree.trigger('add', newlist);
              newlist.animate({height:'toggle'}, 'fast');
            });
          },
          error: function() {
            $this.removeClass('loaded');
          },
          cache: false
        });
      }
    });
  });
};

$.fn.setupPanel = function(){
  var numPanels = $('div.panel').length;

  return $(this).each(function(){
    var panel = $(this);
    panel.find('ul').not('ul.nav').setupTree();
    if (numPanels > 1)
      panel.addClass('additional');
  });
};

var updateBodyWidth = function(){
  var w = 0, num = 0;
  $('div.panel').each(function(){
    w += $(this).outerWidth();
    num += 1;
  });

  $('body').width(w + $(window).width()/2);
};

var scrollingTo = false;

var centerPanel = function(panel, to_top) {
  scrollingTo = true;

  var wasCentered = false;

  if (panel.hasClass('centered')) {
    wasCentered = true;
  } else {
    $('div.panel.centered').removeClass('centered');
    panel.addClass('centered');
  }

  var x = panel.position().left + panel.outerWidth()/2 - $(window).width()/2;
  var y = 0;
  var bottom = panel.position().top + panel.outerHeight();
  var link = panel.find('a.current');

  if (!to_top && link.length > 0 && !wasCentered)
    y = link.position().top - $(window).height()/2;

  if (y < 0) {
    y = 0;
    to_top = true;
  }

  if (window.pageYOffset > bottom && !to_top && y == 0)
    to_top = true;

  if (to_top || y > 0)
    $.scrollTo({left:x, top:y}, 'fast', {queue:false, onAfter:function(){ scrollingTo = false }});
  else
    $.scrollTo(x, 'fast', {axis:'x', onAfter:function(){ scrollingTo = false }});
};

var findClosestPanel = function(){
  var left = window.pageXOffset;
  var closest = false;
  var showPanel = null;

  $('div.panel').each(function(){
    var panel = $(this);
    var pos = panel.position().left + panel.outerWidth()/2 - $(window).width()/2;
    var diff = Math.abs(pos - left);

    if (closest === false || diff < closest) {
      closest = diff;
      showPanel = panel;
    } else
      return false;
  });

  return showPanel;
};

$(function(){
  $(window).keydown(function(e){
    if (e.which == 37 || e.which == 39)
      return false;
  });

  $(window).keyup(function(e){
    if (e.which == 37) {
      var panel = findClosestPanel();
      if (!panel)
        return false;

      var obj = panel.prev('div.panel');
      if (obj.length)
        centerPanel(obj);
      else
        centerPanel(panel);
      return false;

    } else if (e.which == 39) {
      var panel = findClosestPanel();
      if (!panel)
        return false;

      var obj = panel.next('div.panel');
      if (obj.length)
        centerPanel(obj);
      else
        centerPanel(panel);
      return false;
    }
  });

  /*
  var scrollTimeout = null;
  $(window).scroll(function(){
    if (scrollingTo)
      return;

    if (scrollTimeout) {
      clearTimeout(scrollTimeout);
      scrollTimeout = 0;
    }

    scrollTimeout = setTimeout(function(){
      scrollTimeout = 0;
      if (scrollingTo)
        return;

      var showPanel = findClosestPanel();
      if (showPanel)
        centerPanel(showPanel);
    }, 200);
  });
  */

  $('div.panel').setupPanel();
  var width = $('div.panel').outerWidth();
  $('body').css('marginLeft', ($(window).width()/2 - width/2) + 'px');

  /*
  var input = $('#query input');
  var updateSubnav = function(){
    if (inputVal == input.val()) return;
    inputVal = input.val();

    input.siblings('.objects').html('<center><img src="/demo/spinner.gif" align="absmiddle" /></center>');

    $.getJSON(
      '/subnav',
      { where: JSON.stringify(input.val()) },
      function(obj){
        input.siblings('.objects').text(obj.count + ' object' + (obj.count==1 ? '' : 's'));
      }
    );
  };

  input.blur(updateSubnav);
  input.focus(function(){ input.css({padding: '5px 10px 5px 5px', textAlign: 'left'}) })
       .blur( function(){ input.css({padding: '5px', textAlign: 'center'}) });

  input.blur();
  */

  var form = $('form#search');

  $('ul.nav li a:not(.popout)').live('click', function(){
    var nav = $(this).parents('ul.nav:first');
    nav.find('a.selected').removeClass('selected');
    $(this).addClass('selected');

    var panel = $(this).parents('div.panel:first');
    panel.nextAll().remove();
    panel.find('> div.content').html('<center><img src="/demo/spinner.gif" style="margin: auto"></center>');

    $.get(this.href, function(html){
      var newPanel = $(html);
      panel.replaceWith(newPanel);
      newPanel.setupPanel();
      updateBodyWidth();
      centerPanel(newPanel, true);
    });

    return false;
  });

  $('div.panel .content a').live('click', function(){
    var link = $(this);
    var curPanel = $(this).parents('div.panel:first');

    curPanel.find('a.current').removeClass('current');
    link.addClass('current');

    var panel = $('<div class="panel additional"><center><img src="/demo/spinner.gif"></center></div>');
    curPanel.nextAll().remove().end().after(panel);

    $.get(this.href, function(html){
      link.addClass('current');

      var newPanel = $(html);
      panel.replaceWith(newPanel);
      newPanel.setupPanel();
      updateBodyWidth();
      centerPanel(newPanel, true);
    });

    return false;
  });

  $('div.panel ul.nav li.group select.group_key').live('change', function(){
    var select = $(this);
    var link = select.parents('a:first');
    link.attr('href', link.attr('href').replace(/&key=.*$/,'') + "&key=" + select.val());
    link.click();
  });

  $('div#menubar select.collection').live('change', function(){
    var select = $(this);
    window.location = '/db/' + select.val();
  });
});
