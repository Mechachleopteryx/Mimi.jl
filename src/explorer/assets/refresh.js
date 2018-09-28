// Mimi UI

function refresh(speclist) {
    
    // Loop over the things that we want to show in the list, add
    // one button for each element as a child to the variablelist div

    var element = document.getElementById("variablelist");

    for (var i in speclist) {

        var newButton = document.createElement("button");
        newButton.setAttribute("class", "tab");
        
        // Set onclick for button
        newButton.onclick = (function() {

            var name = speclist[i]["name"]
            var id = i
            return function() {
                sendMessageToJulia({cmd: 'display_spec', name: name, id: id})
            }
        })()

        // // Return a closure with a copy of the spec that's private to the function
        // newButton.onclick = (function() {
        //     var spec = speclist[i]["VLspec"];

        //     return function() {
        //         vegaEmbed("#vis", spec, {actions: false});
        //     }
        // }())

        newButton.appendChild(document.createTextNode(speclist[i]["name"]));
        element.appendChild(newButton);
    }
}

function display(speclist, id) {

    var spec = speclist[id]["VLspec"];
    vegaEmbed("#vis", spec, {actions: false});
    
}
