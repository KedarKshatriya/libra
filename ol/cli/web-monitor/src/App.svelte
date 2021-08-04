<script>
  import Main from "./components/layout/Main.svelte";
  import { Router, Route } from "svelte-navigator";
  import ValidatorPage from "./components/validators/ValidatorModal.svelte";
  export let url = "";
</script>

<div>
<Router url="{url}">
	<div>
    <Route path="validator-info/*" >
        <Route path=":address" let:params >
            <ValidatorPage address={params.address} />
        </Route> 
    </Route>

	<Route path="/"><Main /></Route> 
	</div>
</Router>
</div>
