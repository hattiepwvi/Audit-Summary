const { execSync } = require('child_process');
const fs = require('fs');

function verify() {
  const deployments = JSON.parse(fs.readFileSync('deployments.json', 'utf-8'));

  for (const [contractName, data] of Object.entries(deployments)) {
    let cmd = `npx hardhat verify ${data.address}`;
    if (data.parameters && data.parameters.length > 0) {
      cmd += ` ${data.parameters.join(' ')}`;
    }
    cmd += ` --network goerli`;
    console.log(`Verifying ${contractName}...`);
    try {
      execSync(cmd, { stdio: 'inherit' });
    } catch (err) {
      console.error(`Failed to verify ${contractName}:`, err);
    }
  }
}

verify();
