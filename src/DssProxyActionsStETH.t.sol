// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.6.12;

import "ds-test/test.sol";

import {DssProxyActionsStETH, DssProxyActionsEndStETH} from "./DssProxyActionsStETH.sol";
import {DssProxyActions, DssProxyActionsEnd} from "dss-proxy-actions/DssProxyActions.sol";

import {DssDeployTestBase, GemJoin, DSToken} from "dss-deploy/DssDeploy.t.base.sol";
import {DSValue} from "ds-value/value.sol";
import {DssCdpManager} from "dss-cdp-manager/DssCdpManager.sol";
import {ProxyRegistry, DSProxyFactory, DSProxy} from "proxy-registry/ProxyRegistry.sol";

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
    address dssProxyActionsStETH;
    address dssProxyActionsEndStETH;

    function open(address, bytes32, address) public returns (uint256 cdp) {
        bytes memory response = proxy.execute(dssProxyActions, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }

    function give(address, uint256, address) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function lockStETH(address, uint256, uint256) public {
        proxy.execute(dssProxyActionsStETH, msg.data);
    }

    function safeLockStETH(address, uint256, uint256, address) public {
        proxy.execute(dssProxyActionsStETH, msg.data);
    }

    function freeStETH(address, uint256, uint256) public {
        proxy.execute(dssProxyActionsStETH, msg.data);
    }

    function exitStETH(address, uint256, uint256) public {
        proxy.execute(dssProxyActionsStETH, msg.data);
    }

    function lockStETHAndDraw(address, address, address, uint256, uint256, uint256) public {
        proxy.execute(dssProxyActionsStETH, msg.data);
    }

    function openLockStETHAndDraw(address, address, address, bytes32, uint256, uint256) public returns (uint256 cdp) {
        bytes memory response = proxy.execute(dssProxyActionsStETH, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }

    function wipeAndFreeStETH(address, address, uint256, uint256, uint256) public {
        proxy.execute(dssProxyActionsStETH, msg.data);
    }

    function wipeAllAndFreeStETH(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActionsStETH, msg.data);
    }

    function end_freeStETH(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsEndStETH, abi.encodeWithSignature("freeStETH(address,address,uint256)", a, b, c));
    }

    function end_pack(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("pack(address,address,uint256)", a, b, c));
    }

    function end_cashStETH(address a, address b, bytes32 c, uint256 d) public {
        proxy.execute(dssProxyActionsEndStETH, abi.encodeWithSignature("cashStETH(address,address,bytes32,uint256)", a, b, c, d));
    }
}

contract DssProxyActionsTest is DssDeployTestBase, ProxyCalls {
    DssCdpManager manager;

    ProxyRegistry registry;
    DSToken stETH;
    WstETH wstETH;
    DSValue pipWSTETH;
    GemJoin wstETHJoin;

    function setUp() public override {
        super.setUp();
        deployKeepAuth();

        // Add a wstETH token collateral
        stETH = new DSToken("STETH");
        stETH.mint(1000 ether);
        wstETH = new WstETH(stETH, "WSTETH");
        wstETH.mint(1000 ether);
        wstETHJoin = new GemJoin(address(vat), "WSTETH", address(wstETH));
        pipWSTETH = new DSValue();
        dssDeploy.deployCollateralFlip("WSTETH", address(wstETHJoin), address(pipWSTETH));
        pipWSTETH.poke(bytes32(uint256(50 ether))); // Price 50 DAI = 1 WSTETH (in precision 18)
        this.file(address(spotter), "WSTETH", "mat", uint256(1500000000 ether)); // Liquidation ratio 150%
        this.file(address(vat), bytes32("WSTETH"), bytes32("line"), uint256(10000 * RAD));
        spotter.poke("WSTETH");
        (,, uint256 spot,,) = vat.ilks("WSTETH");
        assertEq(spot, 50 * RAY * RAY / 1500000000 ether);

        manager = new DssCdpManager(address(vat));
        DSProxyFactory factory = new DSProxyFactory();
        registry = new ProxyRegistry(address(factory));
        dssProxyActions = address(new DssProxyActions());
        dssProxyActionsEnd = address(new DssProxyActionsEnd());
        dssProxyActionsStETH = address(new DssProxyActionsStETH(address(vat), address(manager)));
        dssProxyActionsEndStETH = address(new DssProxyActionsEndStETH(address(vat), address(manager)));
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
        this.lockStETH(address(wstETHJoin), cdp, 2 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(2 ether));
        assertEq(stETH.balanceOf(address(this)), prevBalance - 2 ether);
    }

    function testSafeLockStETH() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        stETH.approve(address(proxy), 2 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), 0);
        uint256 prevBalance = wstETH.balanceOf(address(this));
        this.safeLockStETH(address(wstETHJoin), cdp, 2 ether, address(proxy));
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(2 ether));
        assertEq(stETH.balanceOf(address(this)), prevBalance - 2 ether);
    }

    function testLockStETHOtherCDPOwner() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        this.give(address(manager), cdp, address(123));
        stETH.approve(address(proxy), 2 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), 0);
        uint256 prevBalance = wstETH.balanceOf(address(this));
        this.lockStETH(address(wstETHJoin), cdp, 2 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)),wstETH.getWstETHByStETH(2 ether));
        assertEq(stETH.balanceOf(address(this)), prevBalance - 2 ether);
    }

    function testFailSafeLockStETHOtherCDPOwner() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        this.give(address(manager), cdp, address(123));
        stETH.approve(address(proxy), 2 ether);
        this.safeLockStETH(address(wstETHJoin), cdp, 2 ether, address(321));
    }

    function testFreeStETH() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        stETH.approve(address(proxy), 2.756 ether);
        uint256 prevBalance = stETH.balanceOf(address(this));
        this.lockStETH(address(wstETHJoin), cdp, 2.756 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(2.756 ether));
        // Due to wrap precision loss the stored wstETH is equivalent to 1 wei less of stETH
        assertEq(wstETH.getStETHByWstETH(ink("WSTETH", manager.urns(cdp))), 2.756 ether - 1);
        this.freeStETH(address(wstETHJoin), cdp, 1.23 ether);
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
        this.lockStETHAndDraw(address(jug), address(wstETHJoin), address(daiJoin), cdp, 2 ether, 10 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(2 ether));
        assertEq(dai.balanceOf(address(this)), 10 ether);
        assertEq(stETH.balanceOf(address(this)), prevBalance - 2 ether);
    }

    function testOpenLockStETHAndDraw() public {
        stETH.approve(address(proxy), 2 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        uint256 prevBalance = stETH.balanceOf(address(this));
        uint256 cdp = this.openLockStETHAndDraw(address(jug), address(wstETHJoin), address(daiJoin), "WSTETH", 2 ether, 10 ether);
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(2 ether));
        assertEq(dai.balanceOf(address(this)), 10 ether);
        assertEq(stETH.balanceOf(address(this)), prevBalance - 2 ether);
    }

    function testWipeAndFreeStETH() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        stETH.approve(address(proxy), 2 ether);
        uint256 prevBalance = stETH.balanceOf(address(this));
        this.lockStETHAndDraw(address(jug), address(wstETHJoin), address(daiJoin), cdp, 2 ether, 10 ether);
        dai.approve(address(proxy), 8 ether);
        this.wipeAndFreeStETH(address(wstETHJoin), address(daiJoin), cdp, 1.5 ether, 8 ether);
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
        this.lockStETHAndDraw(address(jug), address(wstETHJoin), address(daiJoin), cdp, 2 ether, 10 ether);
        dai.approve(address(proxy), 10 ether);
        this.wipeAllAndFreeStETH(address(wstETHJoin), address(daiJoin), cdp, 1.5 ether);
        // Due to unwrap precision loss an extra 1 wei of ink resides in the vault
        assertEq(ink("WSTETH", manager.urns(cdp)), wstETH.getWstETHByStETH(0.5 ether) + 1);
        assertEq(art("WSTETH", manager.urns(cdp)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        // Due to unwrap precision loss the returned stETH is 1 wei less than requested
        assertEq(stETH.balanceOf(address(this)), prevBalance - 0.5 ether - 1);
    }

    function testExitStETH() public {
        uint256 cdp = this.open(address(manager), "WSTETH", address(proxy));
        uint256 prevBalance = stETH.balanceOf(address(this));

        // explicitly join wStETH
        stETH.approve(address(wstETH), 2 ether);
        uint256 wrapped = wstETH.wrap(2 ether);
        wstETH.approve(address(wstETHJoin), wrapped);
        wstETHJoin.join(manager.urns(cdp) ,wrapped);
        assertEq(stETH.balanceOf(address(this)), prevBalance - 2 ether);

        this.exitStETH(address(wstETHJoin), cdp, 2 ether);
        assertEq(stETH.balanceOf(address(this)), prevBalance);
    }

    function testEnd() public {
        stETH.approve(address(proxy), 1 ether);
        uint256 cdp = this.openLockStETHAndDraw(address(jug), address(wstETHJoin), address(daiJoin), "WSTETH", 1 * 10 ** 18, 5 ether);

        this.cage(address(end));
        end.cage("WSTETH");

        (uint256 inkV, uint256 artV) = vat.urns("WSTETH", manager.urns(cdp));
        assertEq(inkV, wstETH.getWstETHByStETH(1 ether));
        assertEq(artV, 5 ether);

        uint256 prevBalanceStETH = stETH.balanceOf(address(this));
        this.end_freeStETH(address(wstETHJoin), address(end), cdp);
        (inkV, artV) = vat.urns("WSTETH", manager.urns(cdp));
        assertEq(inkV, 0);
        assertEq(artV, 0);
        uint256 remainInkVal = (wstETH.getWstETHByStETH(1 ether) - 5 * end.tag("WSTETH") / 10 ** 9); // 1 worth of 1 StETH (deposited) - 5 DAI debt * WSTETH cage price
        assertEq(stETH.balanceOf(address(this)), prevBalanceStETH + wstETH.getStETHByWstETH(remainInkVal));

        end.thaw();

        end.flow("WSTETH");

        dai.approve(address(proxy), 5 ether);
        this.end_pack(address(daiJoin), address(end), 5 ether);

        this.end_cashStETH(address(wstETHJoin), address(end), "WSTETH", 5 ether);
        assertEq(stETH.balanceOf(address(this)), prevBalanceStETH + 1 ether - 1); // (-1 rounding)
    }
}
