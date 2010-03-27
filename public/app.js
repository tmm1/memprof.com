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
        var url = sublist.attr('url');

        $.ajax({
          url: url,
          success: function(data) {
            sublist.animate({height: '0'}, 'fast', function(){
              var panel = $this.parents('div.panel:first');
              var hash = panel.attr('url') || '';
              panel.attr('url', hash + '//TOGGLE=' + url.replace(/^\/dump\/.+?\//,''));
              updateHash();
              replayNext(panel);

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

    panel.find('pre.prettyprint').prettify();

    updateHash();
    replayNext(panel);
  });
};

$.fn.prettify = function(){
  return $(this).each(function(){
    var container = $(this);
    if (container.hasClass('prettified'))
      return;
    container.addClass('prettified');
    container.html(prettyPrintOne(container.html()));
  });
};

var replayNext = function(panel){
  var link = REPLAY.shift();
  if (link) {
    setTimeout(function(){
      if (link.match(/^TOGGLE=/)) {
        var ul = panel.find("ul[url*="+link.slice(7)+"]");
        if (ul.length) {
          ul.prevAll('div.hitarea:first').click();
        }
      } else if (link.match(/^CHANGE=/)) {
        var select = $('select.group_key:last');
        select.val(link.slice(7)).change();
      } else {
        var links = panel.find("a[href*='"+link+"']");
        if (links.length > 0)
          links.eq(0).click();
        else
          REPLAY = [];
      }
    }, 300);
  }
};

var updateHash = function(){
  var hash = '';

  $('div.panel').each(function(){
    hash += ($(this).attr('url') || '');
    var current = $(this).find('a.current');
    if (current.length > 0)
      hash += ('//' + current.attr('href').replace(/^\/dump\/.+?\//,''));
  });

  if (hash)
    window.location.hash = hash;
}

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

  var after = function(){
    scrollingTo = false;
  }

  if (to_top || y > 0)
    $.scrollTo({left:x, top:y}, 'fast', {queue:false, onAfter:after});
  else
    $.scrollTo(x, 'fast', {axis:'x', onAfter:after});
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

$('ul.nav li a:not(.popout)').live('click', function(){
  var link = $(this);
  var nav = $(this).parents('ul.nav:first');
  nav.find('a.selected').removeClass('selected');
  $(this).addClass('selected');

  var panel = $(this).parents('div.panel:first');
  panel.nextAll('div.panel').remove();
  panel.find('> div.content').html('<center><img src="/demo/spinner.gif" style="margin: auto"></center>');

  $.ajax({
    url: this.href,
    success: function(html){
      var newPanel = $(html);
      var hash = panel.attr('url') || '';
      var link_text = $.trim(link.text());

      panel.replaceWith(newPanel);

      if (link_text.match(/^group\s*by/))
        newPanel.attr('url', hash + '//CHANGE=' + escape($.trim($('select.group_key').val())));
      else
        newPanel.attr('url', hash + '//' + link.attr('href').replace(/^\/dump\/.+?\//,''));

      newPanel.setupPanel();

      updateBodyWidth();
      centerPanel(newPanel, true);
    },
    cache: false
  });

  return false;
});

$('div.panel .content a').live('click', function(){
  var link = $(this);
  var curPanel = $(this).parents('div.panel:first');

  curPanel.find('a.current').removeClass('current');
  link.addClass('current');

  var panel = $('<div class="panel additional"><center><img src="/demo/spinner.gif"></center></div>');
  curPanel.nextAll('div.panel').remove().end().after(panel);

  $.ajax({
    url: this.href,
    success: function(html){
      link.addClass('current');

      var newPanel = $(html);
      panel.replaceWith(newPanel);
      newPanel.setupPanel();

      updateBodyWidth();
      centerPanel(newPanel, true);
    },
    cache: false
  });

  return false;
});

$('div.panel ul.nav li.group select.group_key').live('change', function(){
  var select = $(this);
  var link = select.parents('a:first');
  link.attr('href', link.attr('href').replace(/group:[a-z]+/,'group:'+select.val()));
  link.click();
});

$('div#menubar select.collection').live('change', function(){
  var select = $(this);
  window.location = '/dump/' + select.val();
});

$(function(){
  jQuery("abbr.timeago").timeago();

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

  REPLAY = window.location.hash.split('//').slice(1);
  if (REPLAY.length > 0) {
    var old = REPLAY;
    REPLAY = [];
    for (key in old) {
      REPLAY.push(unescape(old[key]));
    }
  }


  var panel = $('div.panel')
  panel.setupPanel();

  var width = panel.outerWidth();
  $('body').css('marginLeft', ($(window).width()/2 - width/2) + 'px');

  $('pre.prettyprint').prettify();
  $('a[rel*=facebox]').facebox();
});
