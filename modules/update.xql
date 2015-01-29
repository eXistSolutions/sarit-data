xquery version "3.1";

(:~
 : Download data from the sarit github repository.
 : 
 : Note: github api is limited to 60 requests per hour from one IP. 
 :)
module namespace gh="http://exist-db.org/apps/sarit/github-update";

declare namespace xi="http://www.w3.org/2001/XInclude";

import module namespace http="http://expath.org/ns/http-client";
import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://existsolutions.com/apps/sarit-data/config" at "config.xqm";
import module namespace console="http://exist-db.org/xquery/console" at "java:org.exist.console.xquery.ConsoleModule";

declare function gh:get-corpus() as xs:string* {
    let $url := $config:github-root || "contents/saritcorpus.xml"
    let $request := <http:request method="GET" href="{$url}" timeout="30"/>
    let $response := http:send-request($request)
    return
        if ($response[1]/@status = "200") then
            let $content := parse-json(util:binary-to-string($response[2]))?content
            let $corpus := parse-xml(util:binary-to-string($content))
            return
                $corpus//xi:include/@href/string()
        else
            ()
};

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
    let $corpus := gh:get-corpus()
    return 
        if (exists($corpus)) then
            templates:process($node/*, map:new(($model, map { "corpus": $corpus })))
        else
            <p>Failed to load data!</p>
};

declare
    %templates:wrap
function gh:files($node as node(), $model as map(*)) {
    for $item in $model("corpus")
    return
        <tr>
            { console:log($item) }
            <td>
            {
                $item
            }
            </td>
            <td>
            {
                if (doc-available($config:data-root || "/" || $item)) then
                    let $modified := xmldb:last-modified($config:data-root, $item)
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
        gh:get-archive-and-update($model("corpus"))
    else
        ()
};

declare %private function gh:get-archive-and-update($corpus as xs:string*) {
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
                for $file in gh:unpack($corpus, $response[2])
                return
                    <li>{$file}</li>
            }
            </ul>
        ) else
            <p>Update Failed: {$response[1]/@status || " " || $response[1]/@message }</p>
};

declare %private function gh:unpack($corpus as xs:string*, $zip as xs:base64Binary) {
    compression:unzip($zip, function($path, $type, $param) {
        replace($path, ".*/([^/]+)$", "$1") = $corpus
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