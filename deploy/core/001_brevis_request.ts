import * as dotenv from 'dotenv';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { verify } from '../utils/utils';

dotenv.config();

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const proof = await deployments.get('BrevisProof');
  const args = ["0x58b529F9084D7eAA598EB3477Fe36064C5B7bbC1", proof.address, "0xB869fC71BEa0880E44dcFf4Ca338F5bEF0a3D0fb"];
  const deployment = await deploy('BrevisRequest', {
    from: deployer,
    log: true,
    args: args,
    proxy: {
      proxyContract: 'OptimizedTransparentProxy',
      execute: {
        init: {
          methodName: 'init',
          args: args
        }
      }
    }
  });
  await verify(hre, deployment, args);
};

deployFunc.tags = ['BrevisRequest'];
deployFunc.dependencies = [];
export default deployFunc;
