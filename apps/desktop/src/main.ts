import App from "./App.svelte";
import { mount } from "svelte";

const target = document.getElementById("app");

if (!target) {
  throw new Error("Loopwire desktop root element was not found.");
}

export default mount(App, { target });
