'use strict';

const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { increaseTo } = require('@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time');

const { expect } = require('chai');
const { parse } = require('dotenv');
const { BigNumber } = require('ethers');
const { ethers, hardhatArguments } = require('hardhat');
const { actions } = require('./helpers/signAndParse');
const { generateSignature } = require('./helpers/generateSignature');
const { parseUnits } = require('ethers/lib/utils');
// eslint-disable-next-line max-lines-per-function
describe('Seneca Contract', () => {

    async function deployTestingFixture() {
        const [owner, addr1, addr2, addr3] = await ethers.getSigners();

        // TO BE UPDATED PER DEPLOYMENT
        const ChamberAddress = '0xF804ba54FC4a533991a825BA4ff0165FE39b51A0';
        const BentoBoxAddress = '0x6Aa8986080085791e9872432b8603C2198d7aA18';
        const senUSDAddress = '0x649eEDEF5729c0581cB9DdA2d01770D7BDbDcF06';
        const mockEthAddress = '0x7A51f19c68181759D4827cB623D70Dfd6110Cab7';
        const chamberMasterAddress = '0xbfbD65F38f97dBcD647c8B32290a9C55D5518a84';
        const CloneContractAddress = '0xF804ba54FC4a533991a825BA4ff0165FE39b51A0';
        const MarketLensAddress = '0xebB397119fb6FF976fD6034F3dC7cD43a47C966E';

        const chamber = await hre.ethers.getContractAt("ChamberFlat", ChamberAddress);
        const senUsd = await hre.ethers.getContractAt("SenecaUSD", senUSDAddress);
        
        const BentoBox = await ethers.getContractAt("BentoBoxV1", BentoBoxAddress);
      
        const mock = await hre.ethers.getContractAt("ERC20Mock", mockEthAddress);

        const chamberFlatMasterContract = chamberMasterAddress; // chamberFlat
      
        const collateral = mockEthAddress; // wETH
      
        const cloneAddress = CloneContractAddress;
      
        const marketLens = await hre.ethers.getContractAt("MarketLens", MarketLensAddress);
        return {
          owner, addr1, addr2, addr3, BentoBox, chamberFlatMasterContract, senUsd, chamber, collateral, cloneAddress, mock, marketLens 
        };
  }

    describe('SUCCESS SCENARIOS', () => {
        it('it should connect to every contract', async () => {
          const { chamber , BentoBox, mock, marketLens } = await loadFixture(
                deployTestingFixture,
            );
            expect(BentoBox.address).to.not.equal(0);
            expect(chamber.address).to.not.equal(0);
            expect(mock.address).to.not.equal(0);
            expect(marketLens.address).to.not.equal(0);
        });

        it('should successfully execute cook with parsed signature', async () => {
            const { addr1, cloneAddress, BentoBox, mock, chamberFlatMasterContract } = await loadFixture(deployTestingFixture);
        
            const nonce = await BentoBox.nonces(addr1.address);
        
            const domainData = {
                name: 'BentoBox V1',
                chainId: 31337,
                verifyingContract: BentoBox.address
            };
        
            const messageData = {
                warning: 'Give FULL access to funds in (and approved to) BentoBox?',
                user: addr1.address,
                masterContract: chamberFlatMasterContract,
                approved: true,
                nonce
            };
        
            const { v, r, s } = await generateSignature(addr1, domainData, messageData);
        
            let cookData = { events: [], values: [], datas: [] };
            
        
            const chamberFlatClone = await ethers.getContractAt("ChamberFlat", cloneAddress)
            await mock.mint(addr1.address, parseUnits('10', 18));
            await mock.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));

        
            cookData = actions.bentoSetApproval(cookData, addr1.address, chamberFlatMasterContract, true, v, r, s);
            
            await chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas);
        });
        it('should successfully execute a deposit cook with signature', async () => {
            const { addr1, cloneAddress, BentoBox, mock, chamberFlatMasterContract, marketLens } = await loadFixture(deployTestingFixture);
        
            const nonce = await BentoBox.nonces(addr1.address);
        
            const domainData = {
                name: 'BentoBox V1',
                chainId: 31337,
                verifyingContract: BentoBox.address
            };
        
            const messageData = {
                warning: 'Give FULL access to funds in (and approved to) BentoBox?',
                user: addr1.address,
                masterContract: chamberFlatMasterContract,
                approved: true,
                nonce
            };
        
            const { v, r, s } = await generateSignature(addr1, domainData, messageData);
        
            let cookData = { events: [], values: [], datas: [] };
            
        
            const chamberFlatClone = await ethers.getContractAt("ChamberFlat", cloneAddress)
            await mock.mint(addr1.address, parseUnits('10', 18));
            const balance = await mock.balanceOf(addr1.address);
            await mock.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));
        
            cookData = actions.bentoSetApproval(cookData, addr1.address, chamberFlatMasterContract, true, v, r, s);
            
            cookData = actions.updateExchangeRate(cookData, true, 0x00, 0x00);
            
            cookData = actions.bentoDeposit(cookData, mock.address, addr1.address, parseUnits('1', 18), parseUnits('1', 18));

            cookData = actions.addCollateral(cookData, parseUnits('1', 18,), addr1.address, false);
            
            await chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas);
            const userPosition = await marketLens.getUserPosition(cloneAddress, addr1.address);
            expect(userPosition.collateral.amount).to.equal(BigNumber.from(parseUnits('1', 18)));

        });

        it('should successfully execute borrow 100 senUSD against deposited collateral', async () => {
            const { addr1, cloneAddress, BentoBox, mock, chamberFlatMasterContract, marketLens, senUsd } = await loadFixture(deployTestingFixture);
        
            const nonce = await BentoBox.nonces(addr1.address);
        
            const domainData = {
                name: 'BentoBox V1',
                chainId: 31337,
                verifyingContract: BentoBox.address
            };
        
            const messageData = {
                warning: 'Give FULL access to funds in (and approved to) BentoBox?',
                user: addr1.address,
                masterContract: chamberFlatMasterContract,
                approved: true,
                nonce
            };
        
            const { v, r, s } = await generateSignature(addr1, domainData, messageData);
        
            let cookData = { events: [], values: [], datas: [] };

            const chamberFlatClone = await ethers.getContractAt("ChamberFlat", cloneAddress)
            await mock.mint(addr1.address, parseUnits('10', 18));

            await mock.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));

            cookData = actions.bentoSetApproval(cookData, addr1.address, chamberFlatMasterContract, true, v, r, s);
          
            cookData = actions.updateExchangeRate(cookData, true, 0x00, 0x00);
        
            cookData = actions.bentoDeposit(cookData, mock.address, addr1.address, parseUnits('1', 18), parseUnits('1', 18));
        
            cookData = actions.addCollateral(cookData, parseUnits('1', 18,), addr1.address, false);
            
            cookData = actions.borrow(
                cookData,
                parseUnits('100', 18),
                addr1.address
              );
    
            cookData = actions.bentoWithdraw(
                cookData,
                senUsd.address,
                addr1.address,
                parseUnits('100', 18),
                parseUnits('100', 18),
                0
              );
            
            await chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas);
            const userPosition = await marketLens.getUserPosition(cloneAddress, addr1.address);
            expect(userPosition.borrowValue).to.equal(BigNumber.from(parseUnits('100.5', 18)));
            expect(await senUsd.balanceOf(addr1.address)).to.equal(parseUnits('100', 18));

        });

        
        it('should successfully repay 100 senUSD collateral', async () => {
          const { addr1, cloneAddress, BentoBox, mock, chamberFlatMasterContract, marketLens, senUsd } = await loadFixture(deployTestingFixture);
      
          const nonce = await BentoBox.nonces(addr1.address);
      
          const domainData = {
              name: 'BentoBox V1',
              chainId: 31337,
              verifyingContract: BentoBox.address
          };
      
          const messageData = {
              warning: 'Give FULL access to funds in (and approved to) BentoBox?',
              user: addr1.address,
              masterContract: chamberFlatMasterContract,
              approved: true,
              nonce
          };
      
          const { v, r, s } = await generateSignature(addr1, domainData, messageData);
      
          let cookData = { events: [], values: [], datas: [] };

          const chamberFlatClone = await ethers.getContractAt("ChamberFlat", cloneAddress)

          await mock.mint(addr1.address, parseUnits('10', 18));

          await mock.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));
          await mock.connect(addr1).approve(cloneAddress, parseUnits('10000', 18));
          await mock.connect(addr1).approve(chamberFlatMasterContract, parseUnits('10000', 18));
          await senUsd.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));
          await senUsd.connect(addr1).approve(cloneAddress, parseUnits('10000', 18));
          await senUsd.connect(addr1).approve(chamberFlatMasterContract, parseUnits('10000', 18));

          cookData = actions.bentoSetApproval(cookData, addr1.address, chamberFlatMasterContract, true, v, r, s);
        
          cookData = actions.updateExchangeRate(cookData, true, 0x00, 0x00);

          /* cookData.events.push(8);
          cookData.values.push(0);
          cookData.datas.push(0); */
      
          cookData = actions.bentoDeposit(cookData, mock.address, addr1.address, parseUnits('1', 18), parseUnits('1', 18));
      
          cookData = actions.addCollateral(cookData, parseUnits('1', 18,), addr1.address, false);
          
          actions.borrow(
              cookData,
              parseUnits('100', 18),
              addr1.address
            );
  
          actions.bentoWithdraw(
            cookData,
            senUsd.address,
            addr1.address,
            parseUnits('100', 18),
            parseUnits('100', 18),
            0
          );

          await chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas);
          expect(await senUsd.balanceOf(addr1.address)).to.equal(parseUnits('100', 18));
          cookData = { events: [], values: [], datas: [] };


          cookData = actions.updateExchangeRate(cookData, true, 0x00, 0x00);

          cookData = actions.bentoDeposit(
            cookData,
            senUsd.address,
            addr1.address,
            parseUnits('100', 18),
            parseUnits('0', 18)
          );

          /* cookData.events.push(8);
          cookData.values.push(0);
          cookData.datas.push(0); */

          cookData = actions.getRepayPart(
            cookData,
            BigNumber.from(parseUnits('100', 18))
          );
          const USE_VALUE1 = -1;
          cookData = actions.repay(
            cookData,
            USE_VALUE1,
            addr1.address,
            false
          );
          

          await chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas);
          expect(await senUsd.balanceOf(addr1.address)).to.equal(BigNumber.from(0));

      });
      it('should successfully withdraw deposited collateral', async () => {
        const { addr1, cloneAddress, BentoBox, mock, chamberFlatMasterContract, collateral } = await loadFixture(deployTestingFixture);
    
        const nonce = await BentoBox.nonces(addr1.address);
    
        const domainData = {
            name: 'BentoBox V1',
            chainId: 31337,
            verifyingContract: BentoBox.address
        };
    
        const messageData = {
            warning: 'Give FULL access to funds in (and approved to) BentoBox?',
            user: addr1.address,
            masterContract: chamberFlatMasterContract,
            approved: true,
            nonce
        };
    
        const { v, r, s } = await generateSignature(addr1, domainData, messageData);
    
        let cookData = { events: [], values: [], datas: [] };

        const chamberFlatClone = await ethers.getContractAt("ChamberFlat", cloneAddress)
        await mock.mint(addr1.address, parseUnits('10', 18));
        const balance = await mock.balanceOf(addr1.address);

        await mock.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));

        cookData = actions.bentoSetApproval(cookData, addr1.address, chamberFlatMasterContract, true, v, r, s);
      
        cookData = actions.updateExchangeRate(cookData, true, 0x00, 0x00);
    
        cookData = actions.bentoDeposit(cookData, mock.address, addr1.address, parseUnits('1', 18), parseUnits('1', 18));
    
        cookData = actions.addCollateral(cookData, parseUnits('1', 18), addr1.address, false);
        
        await chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas);

        expect(await mock.balanceOf(addr1.address)).to.equal(parseUnits('9', 18));
        
        cookData = { events: [], values: [], datas: [] };

        cookData = actions.updateExchangeRate(
          cookData,
          false,
          //@ts-ignore hardcoded
          0x00,
          0x00,
          0
        );
  
        cookData = actions.removeCollateral(
          cookData,
          parseUnits('1', 18),
          addr1.address
        );
  
        cookData = actions.bentoWithdraw(
          cookData,
          collateral,
          addr1.address,
          0,
          parseUnits('1', 18)
        );
        await chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas);
        expect(await mock.balanceOf(addr1.address)).to.equal(parseUnits('10', 18));
    });
  });
    
    describe('FAILURE SCENARIOS', () => {
      it('should revert if approval signature is invalid', async () => {
        const { addr1, addr2, cloneAddress, BentoBox, mock, chamberFlatMasterContract } = await loadFixture(deployTestingFixture);
    
        const nonce = await BentoBox.nonces(addr1.address);
    
        const domainData = {
            name: 'BentoBox V1',
            chainId: 31337,
            verifyingContract: BentoBox.address
        };
    
        const messageData = {
            warning: 'Give FULL access to funds in (and approved to) BentoBox?',
            user: addr2.address,
            masterContract: chamberFlatMasterContract,
            approved: true,
            nonce
        };
    
        const { v, r, s } = await generateSignature(addr1, domainData, messageData);
    
        let cookData = { events: [], values: [], datas: [] };
        
    
        const chamberFlatClone = await ethers.getContractAt("ChamberFlat", cloneAddress)
        await mock.mint(addr1.address, parseUnits('10', 18));
        await mock.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));

    
        cookData = actions.bentoSetApproval(cookData, addr1.address, chamberFlatMasterContract, true, v, r, s);
        
        await expect(chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas)).to.be.revertedWith('MasterCMgr: Invalid Signature');
    });
    it('should revert if user did not approve bentobox on collateral token', async () => {
      const { addr1, addr2, cloneAddress, BentoBox, mock, chamberFlatMasterContract } = await loadFixture(deployTestingFixture);
  
      const nonce = await BentoBox.nonces(addr1.address);
  
      const domainData = {
          name: 'BentoBox V1',
          chainId: 31337,
          verifyingContract: BentoBox.address
      };
  
      const messageData = {
          warning: 'Give FULL access to funds in (and approved to) BentoBox?',
          user: addr1.address,
          masterContract: chamberFlatMasterContract,
          approved: true,
          nonce
      };
  
      const { v, r, s } = await generateSignature(addr1, domainData, messageData);
  
      let cookData = { events: [], values: [], datas: [] };
      
  
      const chamberFlatClone = await ethers.getContractAt("ChamberFlat", cloneAddress)
      await mock.mint(addr1.address, parseUnits('10', 18));
      await mock.connect(addr1).approve(addr2.address, parseUnits('10000', 18));

  
      cookData = actions.bentoSetApproval(cookData, addr1.address, chamberFlatMasterContract, true, v, r, s);
      cookData = actions.updateExchangeRate(cookData, true, 0x00, 0x00); 
      cookData = actions.bentoDeposit(cookData, mock.address, addr1.address, parseUnits('1', 18), parseUnits('1', 18));
      cookData = actions.addCollateral(cookData, parseUnits('1', 18,), addr1.address, false);
      
      await expect(chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas)).to.be.revertedWith('BoringERC20: TransferFrom failed');
    });
    it('should fail to borrow due to user insolvency', async () => {
      const { addr1, cloneAddress, BentoBox, mock, chamberFlatMasterContract, marketLens, senUsd } = await loadFixture(deployTestingFixture);
  
      const nonce = await BentoBox.nonces(addr1.address);
  
      const domainData = {
          name: 'BentoBox V1',
          chainId: 31337,
          verifyingContract: BentoBox.address
      };
  
      const messageData = {
          warning: 'Give FULL access to funds in (and approved to) BentoBox?',
          user: addr1.address,
          masterContract: chamberFlatMasterContract,
          approved: true,
          nonce
      };
  
      const { v, r, s } = await generateSignature(addr1, domainData, messageData);
  
      let cookData = { events: [], values: [], datas: [] };

      const chamberFlatClone = await ethers.getContractAt("ChamberFlat", cloneAddress)
      await mock.mint(addr1.address, parseUnits('10', 18));

      await mock.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));

      cookData = actions.bentoSetApproval(cookData, addr1.address, chamberFlatMasterContract, true, v, r, s);
    
      cookData = actions.updateExchangeRate(cookData, true, 0x00, 0x00);
      
      cookData = actions.borrow(
          cookData,
          parseUnits('100', 18),
          addr1.address
        );

      cookData = actions.bentoWithdraw(
          cookData,
          senUsd.address,
          addr1.address,
          parseUnits('100', 18),
          parseUnits('100', 18),
          0
        );
      
      await expect(chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas)).to.be.revertedWith('Chamber: user insolvent');
    });
    it('should fail to repay due to missing approval', async () => {
      const { addr1, cloneAddress, BentoBox, mock, chamberFlatMasterContract, marketLens, senUsd } = await loadFixture(deployTestingFixture);
  
      const nonce = await BentoBox.nonces(addr1.address);
  
      const domainData = {
          name: 'BentoBox V1',
          chainId: 31337,
          verifyingContract: BentoBox.address
      };
  
      const messageData = {
          warning: 'Give FULL access to funds in (and approved to) BentoBox?',
          user: addr1.address,
          masterContract: chamberFlatMasterContract,
          approved: true,
          nonce
      };
  
      const { v, r, s } = await generateSignature(addr1, domainData, messageData);
  
      let cookData = { events: [], values: [], datas: [] };

      const chamberFlatClone = await ethers.getContractAt("ChamberFlat", cloneAddress)

      await mock.mint(addr1.address, parseUnits('10', 18));

      await mock.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));

      cookData = actions.bentoSetApproval(cookData, addr1.address, chamberFlatMasterContract, true, v, r, s);
    
      cookData = actions.updateExchangeRate(cookData, true, 0x00, 0x00);
  
      cookData = actions.bentoDeposit(cookData, mock.address, addr1.address, parseUnits('1', 18), parseUnits('1', 18));
  
      cookData = actions.addCollateral(cookData, parseUnits('1', 18,), addr1.address, false);
      
      actions.borrow(
          cookData,
          parseUnits('100', 18),
          addr1.address
        );

      actions.bentoWithdraw(
        cookData,
        senUsd.address,
        addr1.address,
        parseUnits('100', 18),
        parseUnits('100', 18),
        0
      );

      await chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas);
      expect(await senUsd.balanceOf(addr1.address)).to.equal(parseUnits('100', 18));
      cookData = { events: [], values: [], datas: [] };

      cookData = actions.updateExchangeRate(cookData, true, 0x00, 0x00);

      cookData = actions.bentoDeposit(
        cookData,
        senUsd.address,
        addr1.address,
        parseUnits('100', 18),
        parseUnits('0', 18)
      );

      cookData = actions.getRepayPart(
        cookData,
        parseUnits('100', 18)
      );

      cookData = actions.repay(
        cookData,
        parseUnits('100', 18),
        addr1.address,
        false
      );
      await expect(chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas)).to.be.revertedWith('BoringERC20: TransferFrom failed');
    });
    it('should fail to deposit wrong collateral token', async () => {
      const { addr1, cloneAddress, BentoBox, mock, chamberFlatMasterContract, marketLens } = await loadFixture(deployTestingFixture);
  
      const nonce = await BentoBox.nonces(addr1.address);
  
      const domainData = {
          name: 'BentoBox V1',
          chainId: 31337,
          verifyingContract: BentoBox.address
      };
  
      const messageData = {
          warning: 'Give FULL access to funds in (and approved to) BentoBox?',
          user: addr1.address,
          masterContract: chamberFlatMasterContract,
          approved: true,
          nonce
      };
  
      const { v, r, s } = await generateSignature(addr1, domainData, messageData);
  
      let cookData = { events: [], values: [], datas: [] };
      
  
      const chamberFlatClone = await ethers.getContractAt("ChamberFlat", cloneAddress)
      await mock.mint(addr1.address, parseUnits('10', 18));
      const mocketh = await hre.ethers.getContractFactory("ERC20Mock");
      const mock2 = await mocketh.connect(addr1).deploy('Wrapped Eth','WETH', addr1.address, 1000000000000000);
      await mock2.deployed();
      await mock.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));
      await mock2.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));
      await mock2.connect(addr1).approve(chamberFlatMasterContract, parseUnits('10000', 18));
      await mock2.connect(addr1).approve(cloneAddress, parseUnits('10000', 18));


      cookData = actions.bentoSetApproval(cookData, addr1.address, chamberFlatMasterContract, true, v, r, s);
      
      cookData = actions.updateExchangeRate(cookData, true, 0x00, 0x00);
      
      cookData = actions.bentoDeposit(cookData, mock2.address, addr1.address, parseUnits('1', 18), parseUnits('1', 18));

      cookData = actions.addCollateral(cookData, parseUnits('1', 18,), addr1.address, false);
      
      await expect(chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas)).to.be.revertedWith('BoringERC20: TransferFrom failed');
  });
  it('should fail to borrow due to too much borrow against ltv', async () => {
    const { addr1, cloneAddress, BentoBox, mock, chamberFlatMasterContract, marketLens, senUsd } = await loadFixture(deployTestingFixture);

    const nonce = await BentoBox.nonces(addr1.address);

    const domainData = {
        name: 'BentoBox V1',
        chainId: 31337,
        verifyingContract: BentoBox.address
    };

    const messageData = {
        warning: 'Give FULL access to funds in (and approved to) BentoBox?',
        user: addr1.address,
        masterContract: chamberFlatMasterContract,
        approved: true,
        nonce
    };

    const { v, r, s } = await generateSignature(addr1, domainData, messageData);

    let cookData = { events: [], values: [], datas: [] };

    const chamberFlatClone = await ethers.getContractAt("ChamberFlat", cloneAddress)
    await mock.mint(addr1.address, parseUnits('10', 18));

    await mock.connect(addr1).approve(BentoBox.address, parseUnits('10000', 18));

    cookData = actions.bentoSetApproval(cookData, addr1.address, chamberFlatMasterContract, true, v, r, s);
  
    cookData = actions.updateExchangeRate(cookData, true, 0x00, 0x00);

    cookData = actions.bentoDeposit(cookData, mock.address, addr1.address, parseUnits('1', 18), parseUnits('1', 18));

    cookData = actions.addCollateral(cookData, parseUnits('1', 18,), addr1.address, false);
    
    cookData = actions.borrow(
        cookData,
        parseUnits('10000', 18),
        addr1.address
      );

    cookData = actions.bentoWithdraw(
        cookData,
        senUsd.address,
        addr1.address,
        parseUnits('10000', 18),
        parseUnits('10000', 18),
        0
      );
    
    await expect(chamberFlatClone.connect(addr1).cook(cookData.events, cookData.values, cookData.datas)).to.be.revertedWith('Chamber: user insolvent');

});

  });
});
