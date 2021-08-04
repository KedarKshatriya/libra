<script lang="ts">
    import AutoPay from "../autopay/AutoPay.svelte";
    import "../layout/Style.svelte";
    import { useNavigate } from "svelte-navigator";
    import { chainInfo } from "../../store";
    
    const navigate = useNavigate();
    export let address;
    let validator;
    let data;
    
    chainInfo.subscribe((info_str) => {
        data = JSON.parse(info_str);
    });

    $: if (data.chain_view && data.chain_view.validator_view) {
    validator = data.chain_view.validator_view.find(x => x.account_address === address)
    }
    
    function get_operator_account(validator) {
        let config = validator.validator_config;
        return config && config.operator_account
            ? config.operator_account
            : "Not Found";
    }
    function has_operator_balance(validator) {
        let config = validator.validator_config;
        return config && (config.operator_has_balance != null)
            ? config.operator_has_balance
            : "Not Found";
    }
</script>
{#if validator}
    <div class="uk-container uk-margin-top uk-margin-bottom">
        <i class="uk-text-left" uk-icon="icon: arrow-left; ratio: 1.5" on:click={() => navigate(-1)} />
        <h2 class="uk-text-center uk-text-uppercase uk-text-muted uk-text-light uk-margin-medium-bottom"> Validator Info </h2>
        
        <table class="uk-table">
        <thead>
            <tr>
                <th></th>
                <th></th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td class="uk-table-expand">account address</td>
                <td>{validator.account_address}</td>
            </tr>
            <tr>
                <td>fullnode network address</td>
                <td class="uk-text-break">{validator.full_node_ip}</td>
            </tr>
            <tr>
                <td>validator network address</td>
                <td>{validator.validator_ip}</td>
            </tr>
            <tr>
                <td>epochs validating and mining</td>
                <td>{validator.epochs_validating_and_mining}</td>
            </tr>
            <tr>
                <td>operator account</td>
                <td>{get_operator_account(validator)}</td>
            </tr>
            <tr>
                <td>operator has positive balance</td>
                <td>{has_operator_balance(validator)}</td>
            </tr>
            <tr>
                <td>can create account</td>
                <td>{validator.epochs_since_last_account_creation > 7}</td> <!--TODO move to the serve side?-->
            </tr>
        </tbody>
        </table>
        <AutoPay account={validator}/>
    </div>
{/if}

