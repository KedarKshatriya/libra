import { writable } from 'svelte/store'

export const chainInfo = writable('Chain');
chainInfo.set("{}");

export const validatorInfo = chainInfo;
validatorInfo.set("{}");

let uri = "http://" + location.host + "/vitals";
let uri2 = "http://" + location.host + "/validator";
let sse = new EventSource(uri);
let sse2 = new EventSource(uri2);

sse.onmessage = function (msg) {
  chainInfo.update(existing => msg.data)
}

sse2.onmessage = function (msg) {
  chainInfo.update(existing => msg.data)
}
