const { ethers } = require("ethers");

async function generateSignature(signer, domainData, messageData) {

  const data = {
    domain: domainData,
    message: messageData,
    types: {
        SetMasterContractApproval: [
            { name: 'warning', type: 'string' },
            { name: 'user', type: 'address' },
            { name: 'masterContract', type: 'address' },
            { name: 'approved', type: 'bool' },
            { name: 'nonce', type: 'uint256' },
        ]
    },
    primaryType: 'SetMasterContractApproval',
};

const signature = await signer._signTypedData(data.domain, data.types, data.message)
return ethers.utils.splitSignature(signature);
}

module.exports = { generateSignature };
