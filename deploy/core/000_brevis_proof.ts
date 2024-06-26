import * as dotenv from 'dotenv';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { verify } from '../utils/utils';

dotenv.config();

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const args = ["0x0000000000000000000000000000000000000000"];
  const deployment = await deploy('BrevisProof', {
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

deployFunc.tags = ['BrevisProof'];
deployFunc.dependencies = [];
export default deployFunc;
