xquery version "3.1";

(:~
 : Download data from the sarit github repository.
 : 
 : Note: github api is limited to 60 requests per hour from one IP. 
 :)
module namespace gh="http://exist-db.org/apps/sarit/github-update";

import module namespace http="http://expath.org/ns/http-client";
import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://existsolutions.com/apps/sarit-data/config" at "config.xqm";
import module namespace console="http://exist-db.org/xquery/console" at "java:org.exist.console.xquery.ConsoleModule";
import module namespace xqjson="http://xqilla.sourceforge.net/lib/xqjson";

declare %private function gh:get-tree() as xs:string? {
    let $url := $config:github-root || "git/trees/master"
    let $request := <http:request method="GET" href="{$url}" timeout="30"/>
    let $response := http:send-request($request)
    return
        if ($response[1]/@status = "200") then
            util:binary-to-string($response[2])
        else
            console:log($response[1])
};

declare
    %templates:wrap
function gh:load($node as node(), $model as map(*)) {
    let $data := gh:get-tree()
    return 
        if ($data) then (
            <script type="text/javascript">
            var ghdata = {$data};
            </script>,
            templates:process($node/*, map:new(($model, map { "tree": xqjson:parse-json($data)/pair[@name = "tree"] })))
(:            templates:process($node/*, map:new(($model, map { "tree": parse-json($data)?tree }))):)
        ) else
            <p>Failed to load data!</p>
};

declare
    %templates:wrap
function gh:files($node as node(), $model as map(*)) {
    for $item in $model("tree")/item[ends-with(pair[@name="path"], ".xml")]
    let $path := $item/pair[@name="path"]/text()
(:    for $item in $model("tree")?*:)
(:    let $path := $item?path:)
(:    where ends-with($item?path, ".xml"):)
    return
        <tr>
            { console:log($item) }
            <td>
            {
(:                $item?path:)
                $item/pair[@name="path"]/text()
            }
            </td>
            <td>{
(:                $item?size idiv 1024:)
                $item/pair[@name="size"]/number() idiv 1024
            }</td>
            <td>
            {
                if (doc-available($config:data-root || "/" || $path)) then
                    let $modified := xmldb:last-modified($config:data-root, $path)
                    return
                        $modified
                else
                    "Not stored"
            }
            </td>
        </tr>
};

declare
    %templates:wrap
function gh:update-all($node as node(), $model as map(*), $action as xs:string?) {
    if ($action = "update") then
        gh:get-archive-and-update()
    else
        ()
};

declare %private function gh:get-archive-and-update() {
    let $url := $config:github-root || "zipball/master"
    let $request := <http:request method="GET" href="{$url}" timeout="20" follow-redirect="true"/>
    let $response := http:send-request($request)
    return
        if ($response[1]/@status = "200") then (
            console:log("sarit", $response[1]),
            console:log("sarit", "Retrieved zip from github"),
            gh:clear-data(),
            <ul>
            {
                for $file in gh:unpack($response[2])
                return
                    <li>{$file}</li>
            }
            </ul>
        ) else
            <p>Update Failed: {$response[1]/@status || " " || $response[1]/@message }</p>
};

declare %private function gh:unpack($zip as xs:base64Binary) {
    compression:unzip($zip, function($path, $type, $param) {
        ends-with($path, ".xml")
    }, (), function($path, $type, $data, $param) {
        console:log("sarit", "Storing resource: " || $path || " type: " || $type),
        xmldb:store($config:data-root, replace($path, ".*/([^/]+)$", "$1"), $data)
    }, ())
};

declare %private function gh:clear-data() {
    (
        console:log("sarit", "Removing data collection"),
        if (xmldb:collection-available($config:data-root)) then
            xmldb:remove($config:data-root)
        else
            (),
        xmldb:create-collection($config:app-root, "data")
    )[3]
};