// Place your application-specific JavaScript functions and classes here
// This file is automatically included by javascript_include_tag :defaults

Ajax.Autocompleter.extract_value = 
  function (value, className) {
    var result;

    var elements = 
      value.getElementsByClassName(className, value);
    if (elements && elements.length == 1) {
      result = elements[0].innerHTML.unescapeHTML();
    }

    return result;
};

function setOptionsFrom(parent,child) {
    p = document.getElementById(parent+"_select");
    v = p.options[p.selectedIndex].value;
    arr2 = eval(child+"_value['"+v+"']");
    arr1 = eval(child+"_text['"+v+"']");
    setOptions(child+"_select",arr1,arr2);
}

function setOptions(id,arr1,arr2) {
    e = document.getElementById(id);
    e.options.length = arr1.length;
    for (i=0; i<arr1.length; i++) {
        e.options[i] = new Option(arr1[i],arr2[i],false,false);
    }
}

function checkBoxes(formid,newval) {
    frm = '#' + formid + ' input.check';
    $$(frm).each(function(box) {box.checked=(newval ? true : false)} );
    return false;
}


function showEltOnCondition(menu,elt,cond) {
    if (menu.options[menu.selectedIndex].value == cond) {
        Element.show(elt);
    } else {
        Element.hide(elt);
    }
}

// Enable chaining of onLoad handlers.

function addLoadEvent(func) {
  var oldonload = window.onload;
  if (typeof window.onload != 'function') {
    window.onload = func;
  } else {
    window.onload = function() {
      if (oldonload) {
        oldonload();
      }
      func();
    }
  }
}
