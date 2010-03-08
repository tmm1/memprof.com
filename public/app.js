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
          }
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

  $('div.panel.centered').removeClass('centered');
  panel.addClass('centered');

  var x = panel.position().left + panel.outerWidth()/2 - $(window).width()/2;
  var y = 0;

  if (to_top)
    $.scrollTo({left:x, top:y}, 'fast');
  else
    $.scrollTo(x, 'fast', {axis:'x'});

  scrollingTo = false;
};

$(function(){
  $(window).keydown(function(e){
    if (e.which == 37 || e.which == 39)
      return false;
  });

  $(window).keyup(function(e){
    if (e.which == 37) {
      var obj = $('div.panel.centered').prev('div.panel');
      if (obj.length)
        centerPanel(obj, true);
      return false;

    } else if (e.which == 39) {
      var obj = $('div.panel.centered').next('div.panel');
      if (obj.length)
        centerPanel(obj, true);
      return false;
    }
  });

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

      centerPanel(showPanel);
    }, 200);
  });

  $('div.panel').setupPanel();
  var width = $('div.panel').outerWidth();
  $('body').css('marginLeft', ($(window).width()/2 - width/2) + 'px');

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

  var form = $('form#search');

  $('ul.nav li a').live('click', function(){
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
    link.attr('href', link.attr('href').replace(/&key=\w+?/,'') + "&key=" + select.val());
    link.click();
  });
});
