const func = async function (hre) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer } = await getNamedAccounts();


    await deploy('HATVault', {
        from: deployer,
        args: [],
        log: true,
    });
};
module.exports = func;
func.tags = ['HATVaultImplementation'];
