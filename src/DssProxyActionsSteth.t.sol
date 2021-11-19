// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.6.12;

import "ds-test/test.sol";

import {DssProxyActionsSteth, DssProxyActionsEndSteth} from "./DssProxyActionsSteth.sol";
import {DssProxyActions, DssProxyActionsEnd, DssProxyActionsDsr} from "dss-proxy-actions/DssProxyActions.sol";

import {DssDeployTestBase, GemJoin, Flipper, DSToken} from "dss-deploy/DssDeploy.t.base.sol";
import {DGD} from "dss-gem-joins/tokens/DGD.sol";
import {GemJoin3} from "dss-gem-joins/join-3.sol";
import {GemJoin4} from "dss-gem-joins/join-4.sol";
import {DSValue} from "ds-value/value.sol";
import {DssCdpManager} from "dss-cdp-manager/DssCdpManager.sol";
import {GetCdps} from "dss-cdp-manager/GetCdps.sol";
import {ProxyRegistry, DSProxyFactory, DSProxy} from "proxy-registry/ProxyRegistry.sol";
import {WETH9_} from "ds-weth/weth9.sol";

contract WstETH is DSToken{
    DSToken public stETH;
    uint256 constant public SharesByPooledEth = 955629254121030571;

    constructor(DSToken _stETH, string memory _symbol) DSToken(_symbol) public {
        stETH = _stETH;
    }

    function _getSharesByPooledEth(uint256 _stETHAmount) internal view returns (uint256) {
        return _stETHAmount * SharesByPooledEth / 1e18;
    }

    function _getPooledEthByShares(uint256 _wstETHAmount) internal view returns (uint256) {
        return _wstETHAmount * 1e18 / SharesByPooledEth;
    }

    function wrap(uint256 _stETHAmount) external returns (uint256) {
        require(_stETHAmount > 0, "wstETH: can't wrap zero stETH");
        uint256 wstETHAmount = _getSharesByPooledEth(_stETHAmount);
        balanceOf[msg.sender] = add(balanceOf[msg.sender], wstETHAmount);
        totalSupply= add(totalSupply , wstETHAmount);
        stETH.transferFrom(msg.sender, address(this), _stETHAmount);
        return wstETHAmount;
    }

    function unwrap(uint256 _wstETHAmount) external returns (uint256) {
        require(_wstETHAmount > 0, "wstETH: zero amount unwrap not allowed");
        uint256 stETHAmount = _getPooledEthByShares(_wstETHAmount);
        balanceOf[msg.sender] = sub(balanceOf[msg.sender], _wstETHAmount);
        totalSupply = sub(totalSupply, _wstETHAmount);
        stETH.transfer(msg.sender, stETHAmount);
        return stETHAmount;
    }

    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256) {
        return _getSharesByPooledEth(_stETHAmount);
    }

    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256) {
        return _getPooledEthByShares(_wstETHAmount);
    }
}

contract ProxyCalls {
    DSProxy proxy;
    address dssProxyActions;
    address dssProxyActionsEnd;
    address dssProxyActionsDsr;
    address dssProxyActionsSteth;
    address dssProxyActionsEndSteth;

    function transfer(address, address, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function open(address, bytes32, address) public returns (uint256 cdp) {
        bytes memory response = proxy.execute(dssProxyActions, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }

    function give(address, uint256, address) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function giveToProxy(address, address, uint256, address) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function cdpAllow(address, uint256, address, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function urnAllow(address, address, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function hope(address, address) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function nope(address, address) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function flux(address, uint256, address, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function move(address, uint256, address, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function frob(address, uint256, int256, int256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function frob(address, uint256, address, int256, int256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function quit(address, uint256, address) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function enter(address, address, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function shift(address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function lockETH(address, address, uint256) public payable {
        (bool success,) = address(proxy).call{value: msg.value}(abi.encodeWithSignature("execute(address,bytes)", dssProxyActions, msg.data));
        require(success, "");
    }

    function safeLockETH(address, address, uint256, address) public payable {
        (bool success,) = address(proxy).call{value: msg.value}(abi.encodeWithSignature("execute(address,bytes)", dssProxyActions, msg.data));
        require(success, "");
    }

    function lockGem(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function safeLockGem(address, address, uint256, uint256, address) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function lockStETH(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActionsSteth, msg.data);
    }

    function safeLockStETH(address, address, uint256, uint256, address) public {
        proxy.execute(dssProxyActionsSteth, msg.data);
    }


    function makeGemBag(address) public returns (address bag) {
        address payable target = address(proxy);
        bytes memory data = abi.encodeWithSignature("execute(address,bytes)", dssProxyActions, msg.data);
        assembly {
            let succeeded := call(sub(gas(), 5000), target, callvalue(), add(data, 0x20), mload(data), 0, 0)
            let size := returndatasize()
            let response := mload(0x40)
            mstore(0x40, add(response, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response, size)
            returndatacopy(add(response, 0x20), 0, size)

            bag := mload(add(response, 0x60))

            switch iszero(succeeded)
            case 1 {
                // throw if delegatecall failed
                revert(add(response, 0x20), size)
            }
        }
    }

    function freeETH(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function freeGem(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function freeStETH(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActionsSteth, msg.data);
    }

    function exitETH(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActionsSteth, msg.data);
    }

    function exitGem(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function exitStETH(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActionsSteth, msg.data);
    }

    function draw(address, address, address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function wipe(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function wipeAll(address, address, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function safeWipe(address, address, uint256, uint256, address) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function safeWipeAll(address, address, uint256, address) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function lockETHAndDraw(address, address, address, address, uint256, uint256) public payable {
        (bool success,) = address(proxy).call{value: msg.value}(abi.encodeWithSignature("execute(address,bytes)", dssProxyActions, msg.data));
        require(success, "");
    }

    function openLockETHAndDraw(address, address, address, address, bytes32, uint256) public payable returns (uint256 cdp) {
        address payable target = address(proxy);
        bytes memory data = abi.encodeWithSignature("execute(address,bytes)", dssProxyActions, msg.data);
        assembly {
            let succeeded := call(sub(gas(), 5000), target, callvalue(), add(data, 0x20), mload(data), 0, 0)
            let size := returndatasize()
            let response := mload(0x40)
            mstore(0x40, add(response, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response, size)
            returndatacopy(add(response, 0x20), 0, size)

            cdp := mload(add(response, 0x60))

            switch iszero(succeeded)
            case 1 {
                // throw if delegatecall failed
                revert(add(response, 0x20), size)
            }
        }
    }

    function lockGemAndDraw(address, address, address, address, uint256, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function openLockGemAndDraw(address, address, address, address, bytes32, uint256, uint256) public returns (uint256 cdp) {
        bytes memory response = proxy.execute(dssProxyActions, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }

    function lockStETHAndDraw(address, address, address, address, uint256, uint256, uint256) public {
        proxy.execute(dssProxyActionsSteth, msg.data);
    }

    function openLockStETHAndDraw(address, address, address, address, bytes32, uint256, uint256) public returns (uint256 cdp) {
        bytes memory response = proxy.execute(dssProxyActionsSteth, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }


    function wipeAndFreeETH(address, address, address, uint256, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function wipeAllAndFreeETH(address, address, address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function wipeAndFreeGem(address, address, address, uint256, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function wipeAllAndFreeGem(address, address, address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function wipeAndFreeStETH(address, address, address, uint256, uint256, uint256) public {
        proxy.execute(dssProxyActionsSteth, msg.data);
    }

    function wipeAllAndFreeStETH(address, address, address, uint256, uint256) public {
        proxy.execute(dssProxyActionsSteth, msg.data);
    }

    function end_freeETH(address a, address b, address c, uint256 d) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("freeETH(address,address,address,uint256)", a, b, c, d));
    }

    function end_freeGem(address a, address b, address c, uint256 d) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("freeGem(address,address,address,uint256)", a, b, c, d));
    }

    function end_freeStETH(address a, address b, address c, uint256 d) public {
        proxy.execute(dssProxyActionsEndSteth, abi.encodeWithSignature("freeStETH(address,address,address,uint256)", a, b, c, d));
    }

    function end_pack(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("pack(address,address,uint256)", a, b, c));
    }

    function end_cashETH(address a, address b, bytes32 c, uint256 d) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("cashETH(address,address,bytes32,uint256)", a, b, c, d));
    }

    function end_cashGem(address a, address b, bytes32 c, uint256 d) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("cashGem(address,address,bytes32,uint256)", a, b, c, d));
    }

    function end_cashStETH(address a, address b, bytes32 c, uint256 d) public {
        proxy.execute(dssProxyActionsEndSteth, abi.encodeWithSignature("cashStETH(address,address,bytes32,uint256)", a, b, c, d));
    }

    function dsr_join(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsDsr, abi.encodeWithSignature("join(address,address,uint256)", a, b, c));
    }

    function dsr_exit(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsDsr, abi.encodeWithSignature("exit(address,address,uint256)", a, b, c));
    }

    function dsr_exitAll(address a, address b) public {
        proxy.execute(dssProxyActionsDsr, abi.encodeWithSignature("exitAll(address,address)", a, b));
    }
}

contract FakeUser {
    function doGive(
        DssCdpManager manager,
        uint256 cdp,
        address dst
    ) public {
        manager.give(cdp, dst);
    }
}

contract DssProxyActionsTest is DssDeployTestBase, ProxyCalls {
    DssCdpManager manager;

    GemJoin3 dgdJoin;
    DGD dgd;
    DSValue pipDGD;
    Flipper dgdFlip;
    ProxyRegistry registry;
    WETH9_ realWeth;
    DSToken stETH;
    WstETH wstETH;
    DSValue pipWSTETH;
    GemJoin wstETHJoin;
    Flipper wstETHFlip;

    function setUp() public override {
        super.setUp();
        deployKeepAuth();

        // Create a real WETH token and replace it with a new adapter in the vat
        realWeth = new WETH9_();
        this.deny(address(vat), address(ethJoin));
        ethJoin = new GemJoin(address(vat), "ETH", address(realWeth));
        this.rely(address(vat), address(ethJoin));

        // Add a token collateral
        dgd = new DGD(1000 * 10 ** 9);
        dgdJoin = new GemJoin3(address(vat), "DGD", address(dgd), 9);
        pipDGD = new DSValue();
        dssDeploy.deployCollateralFlip("DGD", address(dgdJoin), address(pipDGD));
        (dgdFlip,,) = dssDeploy.ilks("DGD");
        pipDGD.poke(bytes32(uint256(50 ether))); // Price 50 DAI = 1 DGD (in precision 18)
        this.file(address(spotter), "DGD", "mat", uint256(1500000000 ether)); // Liquidation ratio 150%
        this.file(address(vat), bytes32("DGD"), bytes32("line"), uint256(10000 * 10 ** 45));
        spotter.poke("DGD");
        (,,uint256 spot,,) = vat.ilks("DGD");
        assertEq(spot, 50 * RAY * RAY / 1500000000 ether);

        // Add a wstETH token collateral
        stETH = new DSToken("STETH");
        stETH.mint(1000 ether);
        wstETH = new WstETH(stETH, "WSTETH");
        wstETH.mint(1000 ether);
        wstETHJoin = new GemJoin(address(vat), "WSTETH", address(wstETH));
        pipWSTETH = new DSValue();
        dssDeploy.deployCollateralFlip("WSTETH", address(wstETHJoin), address(pipWSTETH));
        (wstETHFlip,,) = dssDeploy.ilks("WSTETH");
        pipWSTETH.poke(bytes32(uint256(50 ether))); // Price 50 DAI = 1 WSTETH (in precision 18)
        this.file(address(spotter), "WSTETH", "mat", uint256(1500000000 ether)); // Liquidation ratio 150%
        this.file(address(vat), bytes32("WSTETH"), bytes32("line"), uint256(10000 * RAD));
        spotter.poke("WSTETH");
        (,, spot,,) = vat.ilks("WSTETH");
        assertEq(spot, 50 * RAY * RAY / 1500000000 ether);

        manager = new DssCdpManager(address(vat));
        DSProxyFactory factory = new DSProxyFactory();
        registry = new ProxyRegistry(address(factory));
        dssProxyActions = address(new DssProxyActions());
        dssProxyActionsEnd = address(new DssProxyActionsEnd());
        dssProxyActionsDsr = address(new DssProxyActionsDsr());
        dssProxyActionsSteth = address(new DssProxyActionsSteth());
        dssProxyActionsEndSteth = address(new DssProxyActionsEndSteth());
        proxy = DSProxy(registry.build());
    }

    function ink(bytes32 ilk, address urn) public view returns (uint256 inkV) {
        (inkV,) = vat.urns(ilk, urn);
    }

    function art(bytes32 ilk, address urn) public view returns (uint256 artV) {
        (,artV) = vat.urns(ilk, urn);
    }

    function testLockStETH() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        stETH.approve(address(proxy), 2 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), 0);
        uint256 prevBalance = wstETH.balanceOf(address(this));
        this.lockStETH(address(manager), address(wstETHJoin), cdp, 2 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(2 ether));
        assertEq(stETH.balanceOf(address(this)), prevBalance - 2 ether);
    }

    function testSafeLockStETH() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        stETH.approve(address(proxy), 2 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), 0);
        uint256 prevBalance = wstETH.balanceOf(address(this));
        this.safeLockStETH(address(manager), address(wstETHJoin), cdp, 2 ether, address(proxy));
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(2 ether));
        assertEq(stETH.balanceOf(address(this)), prevBalance - 2 ether);
    }

    function testLockStETHOtherCDPOwner() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        this.give(address(manager), cdp, address(123));
        stETH.approve(address(proxy), 2 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), 0);
        uint256 prevBalance = wstETH.balanceOf(address(this));
        this.lockStETH(address(manager), address(wstETHJoin), cdp, 2 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)),wstETH.getWstETHByStETH(2 ether));
        assertEq(stETH.balanceOf(address(this)), prevBalance - 2 ether);
    }

    function testFailSafeLockStETHOtherCDPOwner() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        this.give(address(manager), cdp, address(123));
        stETH.approve(address(proxy), 2 ether);
        this.safeLockStETH(address(manager), address(wstETHJoin), cdp, 2 ether, address(321));
    }

    function testFreeStETH() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        stETH.approve(address(proxy), 2.756 ether);
        uint256 prevBalance = stETH.balanceOf(address(this));
        this.lockStETH(address(manager), address(wstETHJoin), cdp, 2.756 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(2.756 ether));
        // Due to wrap precision loss the stored wstETH is equivalent to 1 wei less of stETH
        assertEq(wstETH.getStETHByWstETH(ink("WSTETH", manager.urns(cdp))), 2.756 ether - 1);
        this.freeStETH(address(manager), address(wstETHJoin), cdp, 1.23 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(1.526 ether));
        // Due to unwrap precision loss the returned stETH is 1 wei less than requested
        assertEq(stETH.balanceOf(address(this)), prevBalance - 1.526 ether - 1);
    }

    function testLockStETHAndDraw() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        stETH.approve(address(proxy), 2 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        uint256 prevBalance = stETH.balanceOf(address(this));
        this.lockStETHAndDraw(address(manager), address(jug), address(wstETHJoin), address(daiJoin), cdp, 2 ether, 10 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(2 ether));
        assertEq(dai.balanceOf(address(this)), 10 ether);
        assertEq(stETH.balanceOf(address(this)), prevBalance - 2 ether);
    }

    function testOpenLockStETHAndDraw() public {
        stETH.approve(address(proxy), 2 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        uint256 prevBalance = stETH.balanceOf(address(this));
        uint256 cdp = this.openLockStETHAndDraw(address(manager), address(jug), address(wstETHJoin), address(daiJoin), "WSTETH", 2 ether, 10 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(2 ether));
        assertEq(dai.balanceOf(address(this)), 10 ether);
        assertEq(stETH.balanceOf(address(this)), prevBalance - 2 ether);
    }

    function testWipeAndFreeStETH() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        stETH.approve(address(proxy), 2 ether);
        uint256 prevBalance = stETH.balanceOf(address(this));
        this.lockStETHAndDraw(address(manager), address(jug), address(wstETHJoin), address(daiJoin), cdp, 2 ether, 10 ether);
        dai.approve(address(proxy), 8 ether);
        this.wipeAndFreeStETH(address(manager), address(wstETHJoin), address(daiJoin), cdp, 1.5 ether, 8 ether);
        // Due to unwrap precision loss an extra 1 wei of ink resides in the vault
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(0.5 ether) + 1);
        assertEq(art("WSTETH", manager.urns(cdp)), 2 ether);
        assertEq(dai.balanceOf(address(this)), 2 ether);
        // Due to unwrap precision loss the returned stETH is 1 wei less than requested
        assertEq(stETH.balanceOf(address(this)), prevBalance - 0.5 ether - 1);
    }

    function testWipeAllAndFreeStETH() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        stETH.approve(address(proxy), 2 ether);
        uint256 prevBalance = stETH.balanceOf(address(this));
        this.lockStETHAndDraw(address(manager), address(jug), address(wstETHJoin), address(daiJoin), cdp, 2 ether, 10 ether);
        dai.approve(address(proxy), 10 ether);
        this.wipeAllAndFreeStETH(address(manager), address(wstETHJoin), address(daiJoin), cdp, 1.5 ether);
        // Due to unwrap precision loss an extra 1 wei of ink resides in the vault
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(0.5 ether) + 1);
        assertEq(art("WSTETH", manager.urns(cdp)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        // Due to unwrap precision loss the returned stETH is 1 wei less than requested
        assertEq(stETH.balanceOf(address(this)), prevBalance - 0.5 ether - 1);
    }

    function testEnd() public {
        uint256 cdp = this.openLockETHAndDraw{value: 2 ether}(address(manager), address(jug), address(ethJoin), address(daiJoin), "ETH", 300 ether);
        col.mint(1 ether);
        col.approve(address(proxy), 1 ether);
        uint256 cdp2 = this.openLockGemAndDraw(address(manager), address(jug), address(colJoin), address(daiJoin), "COL", 1 ether, 5 ether);
        dgd.approve(address(proxy), 1 * 10 ** 9);
        uint256 cdp3 = this.openLockGemAndDraw(address(manager), address(jug), address(dgdJoin), address(daiJoin), "DGD", 1 * 10 ** 9, 5 ether);
        stETH.approve(address(proxy), 1 ether);
        uint256 cdp4 = this.openLockStETHAndDraw(address(manager), address(jug), address(wstETHJoin), address(daiJoin), "WSTETH", 1 * 10 ** 18, 5 ether);

        this.cage(address(end));
        end.cage("ETH");
        end.cage("COL");
        end.cage("DGD");
        end.cage("WSTETH");

        (uint256 inkV, uint256 artV) = vat.urns("ETH", manager.urns(cdp));
        assertEq(inkV, 2 ether);
        assertEq(artV, 300 ether);

        (inkV, artV) = vat.urns("COL", manager.urns(cdp2));
        assertEq(inkV, 1 ether);
        assertEq(artV, 5 ether);

        (inkV, artV) = vat.urns("DGD", manager.urns(cdp3));
        assertEq(inkV, 1 ether);
        assertEq(artV, 5 ether);

        (inkV, artV) = vat.urns("WSTETH", manager.urns(cdp4));
        assertEq(inkV, wstETH.getWstETHByStETH(1 ether));
        assertEq(artV, 5 ether);

        uint256 prevBalanceETH = address(this).balance;
        this.end_freeETH(address(manager), address(ethJoin), address(end), cdp);
        (inkV, artV) = vat.urns("ETH", manager.urns(cdp));
        assertEq(inkV, 0);
        assertEq(artV, 0);
        uint256 remainInkVal = 2 ether - 300 * end.tag("ETH") / 10 ** 9; // 2 ETH (deposited) - 300 DAI debt * ETH cage price
        assertEq(address(this).balance, prevBalanceETH + remainInkVal);

        uint256 prevBalanceCol = col.balanceOf(address(this));
        this.end_freeGem(address(manager), address(colJoin), address(end), cdp2);
        (inkV, artV) = vat.urns("COL", manager.urns(cdp2));
        assertEq(inkV, 0);
        assertEq(artV, 0);
        remainInkVal = 1 ether - 5 * end.tag("COL") / 10 ** 9; // 1 COL (deposited) - 5 DAI debt * COL cage price
        assertEq(col.balanceOf(address(this)), prevBalanceCol + remainInkVal);

        uint256 prevBalanceDGD = dgd.balanceOf(address(this));
        this.end_freeGem(address(manager), address(dgdJoin), address(end), cdp3);
        (inkV, artV) = vat.urns("DGD", manager.urns(cdp3));
        assertEq(inkV, 0);
        assertEq(artV, 0);
        remainInkVal = (1 ether - 5 * end.tag("DGD") / 10 ** 9) / 10 ** 9; // 1 DGD (deposited) - 5 DAI debt * DGD cage price
        assertEq(dgd.balanceOf(address(this)), prevBalanceDGD + remainInkVal);

        uint256 prevBalanceStETH = stETH.balanceOf(address(this));
        this.end_freeStETH(address(manager), address(wstETHJoin), address(end), cdp4);
        (inkV, artV) = vat.urns("WSTETH", manager.urns(cdp4));
        assertEq(inkV, 0);
        assertEq(artV, 0);
        remainInkVal = (wstETH.getWstETHByStETH(1 ether) - 5 * end.tag("WSTETH") / 10 ** 9); // 1 worth of 1 StETH (deposited) - 5 DAI debt * WSTETH cage price
        assertEq(stETH.balanceOf(address(this)), prevBalanceStETH + wstETH.getStETHByWstETH(remainInkVal));

        end.thaw();

        end.flow("ETH");
        end.flow("COL");
        end.flow("DGD");
        end.flow("WSTETH");

        dai.approve(address(proxy), 315 ether);
        this.end_pack(address(daiJoin), address(end), 315 ether);

        this.end_cashETH(address(ethJoin),      address(end), "ETH",    315 ether);
        this.end_cashGem(address(colJoin),      address(end), "COL",    315 ether);
        this.end_cashGem(address(dgdJoin),      address(end), "DGD",    315 ether);
        this.end_cashStETH(address(wstETHJoin), address(end), "WSTETH", 315 ether);

        assertEq(address(this).balance, prevBalanceETH + 2 ether);
        assertEq(col.balanceOf(address(this)), prevBalanceCol + 1 ether);
        assertEq(dgd.balanceOf(address(this)), prevBalanceDGD + 1 * 10 ** 9 - 1); // (-1 rounding)
        assertEq(stETH.balanceOf(address(this)), prevBalanceStETH + 1 ether - 2); // (-2 rounding)
    }

    receive() external payable {}
}
