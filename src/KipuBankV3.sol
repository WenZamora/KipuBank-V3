// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
////  IMPORTS
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

////LIBRERIAS 
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

////INTERFACES

interface IUniswapV2Router02 {
    //funciones para depositar
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
    
    // Función para manejar ETH
    function WETH() external pure returns (address);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

///@title KipuBankV3 
///@author Wendy Zamora
///@notice Permite a usuarios depositar cualquier token swapeable (a USDC) y retirar su saldo en USDC
contract KipuBankV3 is Ownable, ReentrancyGuard  {
    ////DECLARACION DE TIPOS
    using SafeERC20 for IERC20;

    ////CONSTANTES
    address public constant ETH_ADDRESS = address(0);  /////////////////!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    //// VARIABLES
	///@notice variable inmutable para almacenar el umbral fijo que se puede retirar por transaccion
	uint256 public immutable i_maxRetiroUSD;
    /// @notice variable inmutable para almacenar el limite global de depositos
    uint256 public immutable i_bankCapUSD;
    /// @notice variable para el total global del banco **
    uint256 public s_totalDepositosUSDC;
    ///@notice variable para llevar registro del nro de depositos 
    uint256 public s_contDepositos;
    ///@notice variable para llevar registro del nro de retiros
    uint256 public s_contRetiros;
    
    //** Variables para uniswapV2
    ///@notice variable inmutable del Router.
    IUniswapV2Router02 public immutable i_router;
    address public immutable i_USDC; // dir del token base para la contabilidad (USDC).             
    address public immutable i_WETH; // dir del Wrapped ETH (WETH), obtenida del router en el constructor.
    uint256 public s_maxSlippageBps = 100; //***************************

    /// @notice Mapping para el saldo de cada usuario 
    mapping(address => uint256) public s_depositosUSDC;

    //// EVENTOS

	///@notice evento emitido cuando se realiza un deposito nuevo
    event KipuBank_DepositoRecibido(address usuario, address indexed token, uint256 valor);
    ///@notice evento emitido cuando se realiza un retiro
	event KipuBank_RetiroRealizado(address usuario, address indexed token, uint256 valor);
    

    //// ERRORES

    ///@notice error emitido cuando el valor a tranferir hace que se supere el limite global
    error KipuBank_ExcedeLimiteGlobal(uint256 tatal, uint256 valor);
	///@notice error emitido cuando el valor a retirar supera el fondo disponible
    error KipuBank_FondoInsuficiente(uint256 fondo, uint256 valor);
    ///@notice error emitido cuando el monto a retirar es superiror al limite permitido por transaccion
    error KipuBank_SuperaLimiteXTransaccion(uint256 limite, uint256 valor);
	///@notice error emitido cuando falla la transferencia
	error KipuBank_TransferenciaFallida(address token, uint256 valor);
    //@notice error emitido cuando un valor de inicializacion es invalido
    error KipuBank_ValorInvalido(uint256);
    //@notice error emitido cuando el monto ETH no es valido
    error KipuBank_MontoETHInvalido(); 
    // ***
    //@notice error emitido cuando el usuario intenta retirar un token que no es USDC
    error KipuBank_TokenNoSoportado(address token);
    //@notice error emitido si el Router de Uniswap no devuelve ninguna cantidad de USDC (o devuelve 0)
    error KipuBank_SwapFallido();

    //// FUNCIONES ////

    //// CONSTRUCTOR
    ///@param _maxRetiroUSDC Limite por retiro expresado en USDC (USDC tiene 6 decimales)
    ///@param _bankCapUSDC Litime global  exprsado en USDC
    constructor(uint256 _maxRetiroUSDC, uint256 _bankCapUSDC, address _routerAddress, address _usdcAddress) Ownable(msg.sender){// bankCap -> limite del banco // _routerAddress: dir del router // _usdcAddress: dir del USDC 
		//Checks 
        //si el valor (max retiro) es cero, revertir y le paso el valor del MaxRetiro al error 
        if (_maxRetiroUSDC == 0) revert KipuBank_ValorInvalido(_maxRetiroUSDC);
        //Si elvalor es cero, revierto y le paso el valor al error
        if (_bankCapUSDC == 0) revert KipuBank_ValorInvalido(_bankCapUSDC);  

        //Effects
        i_maxRetiroUSD = _maxRetiroUSDC;
        i_bankCapUSD = _bankCapUSDC;

        //inicio la instancia del router y de la dir dek usdc
        i_router = IUniswapV2Router02(_routerAddress);
        i_USDC = _usdcAddress;

        //para obtener la dir del weth del router
        i_WETH = i_router.WETH();
	}

    //**************************************************
    
    function _applySlippage(uint256 expected) private view returns (uint256) {
        // s_maxSlippageBps en basis points (100 bps = 1%).
        uint256 min = (expected * (10000 - s_maxSlippageBps)) / 10000;
        return min;
    }
    ///@notice Realiza el swap de cualquier token (o ETH) a USDC usando Uniswap V2 Router.
    ///@param _token La dirección del token a intercambiar (o ETH_ADDRESS).
    //@param _cantidad La cantidad del token/ETH a intercambiar.
    ///@param _usuario El usuario que inicio la transacción.
    ///@return La cantidad final de USDC recibida desp del swap.
    function _realizarSwapAUsdc( address _token, uint256 _cantidad, address _usuario ) private returns (uint256) { //esta func es la que interactua con el router uniswapV2 -> para convertir el token de entrada en el token destino
        
        address[] memory path = new address[](2); // la ruta (path) define la secuencia de token para el swap -> (token_in, usdc)
        uint256[] memory amounts;
        uint256 deadline = block.timestamp + 300;  // va a ser elmplazo limite -> la Tx debe completarse en los prox 5 min = 300seg
        uint256 cantidadUsdcRecibida;

        if (_token == ETH_ADDRESS) { // Si swap de eth - token nativo
            
            //primero definir la ruta --> ETH va como WETH para el Router
            path[0] = i_WETH; // WETH-> obtenido del router en el constructor
            path[1] = i_USDC; // USDC -> es el token de destino!

            uint[] memory est = i_router.getAmountsOut(_cantidad, path);
            uint256 expectedUSDC = est[1];

            //verifico que el total + un estimado no dupere el limite antes de hacer el swap
            if (s_totalDepositosUSDC + expectedUSDC > i_bankCapUSD) {
                revert KipuBank_ExcedeLimiteGlobal(s_totalDepositosUSDC, expectedUSDC);
            }
            //Calculo amountOutMin 
            uint256 minOut = _applySlippage(expectedUSDC);

            // llamada al Router -> swapExactETHForTokens
            // tengo que usar el `msg.value` que el usurio envia para el swap.
            amounts = i_router.swapExactETHForTokens{value: _cantidad}(minOut, path, address(this), deadline); // minOut: amountOutMin: Calculado previamente // address(this) : el contrato es quien recibe el USDC
            
            cantidadUsdcRecibida = amounts[1];  // el result del swap va a devolver el monto del token de entrada (amounts[0])y la salida (amounts[1])
        } else { // sino - swap de otro ERC20/// El usuario DEBIÓ haber dado 'approve' al KipuBank para este token antes!!
        
            // Transferir el token del usuario al contrato KipuBank ---> El KipuBank debe tener el token ANTES de darselo a uniswap.
            IERC20(_token).safeTransferFrom(_usuario, address(this), _cantidad);

            // Aprobar al router de uniswap --> el KipuBank le tiene q dar permiso al Router para tomar los tokens q fueron transferidos recien
            //allowance definidoseguro
            uint256 currentAllowance = IERC20(_token).allowance(address(this), address(i_router));
            if (currentAllowance < _cantidad) {
                IERC20(_token).safeIncreaseAllowance(address(i_router), _cantidad - currentAllowance);
            }

            //definiendo la ruta
            path[0] = _token;
            path[1] = i_USDC;

            uint[] memory est = i_router.getAmountsOut(_cantidad, path);
            uint256 expectedUSDC = est[1];

            //verifico que el total + un estimado no dupere el limite antes de hacer el swap
            if (s_totalDepositosUSDC + expectedUSDC > i_bankCapUSD) {
                revert KipuBank_ExcedeLimiteGlobal(s_totalDepositosUSDC, expectedUSDC);
            }

            // Calcular amountOutMin
            uint256 minOut = _applySlippage(expectedUSDC);

            // llamada al Router: swapExactTokensForTokens
            amounts = i_router.swapExactTokensForTokens( _cantidad, minOut, path, address(this), deadline ); // _cantidad: amountIn->La cantidad exacta que se quiere intercambiar
            
            cantidadUsdcRecibida = amounts[1];
        }
        
        // Validadcion de seguridad -> revertir si el swap no entregó nada!!
        if (cantidadUsdcRecibida == 0) revert KipuBank_SwapFallido();

        return cantidadUsdcRecibida;
    }

    ///@notice función para recibir los depositos
	///@dev esta función debe sumar el valor depositado por cada usuario a lo largo del tiempo
    ///@dev esta función debe sumar el valor depositado al valor total de depositos ya acumulados
    //@dev esta función debe contar la cantidad de deposutos realizados.
    ///@dev esta función debe emitir un evento informando el deposito.
    ///@param _token Dirección del token a depositar (o ETH_ADDRESS).
    ///@param _cantidad La cantidad a depositar (o msg.value si es ETH).
    function depositar(address _token, uint256 _cantidad) public payable nonReentrant {        //verifico que el deposito no supere el limite global en el modifier
       //Checks
       //valido cant no sea cero
       if(_cantidad == 0) revert KipuBank_ValorInvalido(0);

        uint256 cantidadUsdcRecibida;

        //verifico si se envio ETH uasno no se debe - para el casode tokens erc20
        if(_token != ETH_ADDRESS && msg.value >0 ){
            revert KipuBank_ValorInvalido(msg.value); // No debo enviar ETH con tokens ERC20 
        } 

        //valido si se deposita ETH ->ETH tiene que conicidir con la _cantidad
        if (_token == ETH_ADDRESS && msg.value  != _cantidad) {
            revert KipuBank_MontoETHInvalido();
        }

        if(_token == i_USDC){ // si deposito directi de uscd -> no hay swap
            //como el bacno ya opera en usdc entonces lo almaceno directo
            IERC20(i_USDC).safeTransferFrom(msg.sender, address(this), _cantidad);
            cantidadUsdcRecibida = _cantidad;
        } else { // sinno - el deposito es de otro token o eth --> necesotp swwap
            //con la funcion  _realizarSwapAUsdc manejo la tranferencia, swap y recep
            cantidadUsdcRecibida = _realizarSwapAUsdc(_token, _cantidad, msg.sender);
        }

        //verifico que el total del banco mas la cantidad recibida este dentro del limite
        if (s_totalDepositosUSDC + cantidadUsdcRecibida > i_bankCapUSD) { 
            revert KipuBank_ExcedeLimiteGlobal(s_totalDepositosUSDC, cantidadUsdcRecibida); // cuando revierte, si se hizo el swap se deshace y lso token vuelven al usuario
        }

        //Effects
        s_depositosUSDC[msg.sender] += cantidadUsdcRecibida;//actualizo el saldo 
        s_totalDepositosUSDC +=cantidadUsdcRecibida; //actualizo el total global depositado
        s_contDepositos += 1;

        //interact
        emit KipuBank_DepositoRecibido(msg.sender, i_USDC, cantidadUsdcRecibida); // informa el token base usdc y la cantidad recibida!
    }

    //// RECEIVE & FALLBACK
    /// @notice Permite que el contrato reciba ETH enviado directamente sin calldata.
    /// @dev Redirige el ETH a la lógica de depositar para que se apliquen las validaciones (bankCap).
    receive() external payable{
        depositar(ETH_ADDRESS, msg.value);
    }

    /// @notice Función de reserva que se ejecuta cuando no se encuentra una función.
    /// @dev Si se envía ETH, lo procesa como un depósito (aunque la receive es la preferida).
    fallback() external payable {
        // Si envían ETH con datos desconocidos, también lo tratamos como un depósito
         depositar(ETH_ADDRESS, msg.value); 
    }

    ///@notice función para que el usuario retire fondos de su boveda
	///@param _cantidad El valor a retirar
    ///@param _token Direccion del token a retirar
    ///@dev el valor a retirar debe estar dentro del limite, ademas debe haber fondo suficiente para poder retirar
    ///@dev esta funcion debe contar la cantidad de retiros realizados
    ///@dev esta función debe emitir un evento informando el retiro
    function retirar(address _token, uint256 _cantidad) external nonReentrant {
        //checks 

        //solo se permite retirar token base USDC - Verifico que el usuario quiera retirar usdc
        if(_token != i_USDC){ revert KipuBank_TokenNoSoportado(_token); } // si el usuario pide retiri por ej eth entonces revertir
       
        //verifico que la cantidad no sea cero
        if(_cantidad == 0) revert KipuBank_ValorInvalido(0);

        //verifico que no supere el limite por transaccion
        if (_cantidad > i_maxRetiroUSD) { revert KipuBank_SuperaLimiteXTransaccion(i_maxRetiroUSD, _cantidad); }

        //verifico que los fondos sean suficientes
        if (_cantidad > s_depositosUSDC[msg.sender]) {  revert KipuBank_FondoInsuficiente(s_depositosUSDC[msg.sender], _cantidad); }
        
                
        //effects 
        s_depositosUSDC[msg.sender] -= _cantidad; //actualizo saldo del usuario
        s_totalDepositosUSDC -= _cantidad;//Actualizo el total global depositado
        s_contRetiros += 1; //actualizo el contador

        //interactions
        IERC20(_token).safeTransfer(msg.sender, _cantidad); // solo le tranfiero al usuario el token USDC!!!
        
         

        emit KipuBank_RetiroRealizado(msg.sender, i_USDC, _cantidad); //informo el retiro del token usdc
	}

    ///@notice funcion para ver el fondo disponible
    ///@param usuario usuario del que se quiere conocer los fondos disponibles
    ///@dev esta funcion debe devolver el fondo disponible del usuario
    function verFondoUSDC(address usuario) external view returns (uint256 valor){
        return s_depositosUSDC[usuario];
    }

    ///@notice funcion para ver la cantidad de depositos 
    ///@dev esta funcion debe devolver la cantidad de depositos realizados
    function verContDepositos() external view returns (uint256 valor){
        return s_contDepositos;
    }

    ///@notice funcion para ver la cantidad de retiros 
    ///@dev esta funcion debe devolver la cantidad de retiros realizados
    function verContRetiros() external view returns (uint256 valor){
        return s_contRetiros;
    }

    /// @notice Recupera el valor total de depósitos en el banco, medido en USDC
    /// @return totalUSDC El total de depósitos globales acumulados en USDC
    function verTotalDepositosUSDC() external view returns (uint256 totalUSDC) {
        return s_totalDepositosUSDC;
    }
    /// @notice Recupera el límite máximo que se puede retirar en una sola transacción, medido en USD
    /// @return limiteUSD El límite máximo de retiro por transacción en USD
    function verLimiteRetiroUSD() external view returns (uint256 limiteUSD) {
        return i_maxRetiroUSD;
    }

    function getExpectedUSDC(address token, uint256 amountIn) external view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = token == ETH_ADDRESS ? i_WETH : token;
        path[1] = i_USDC;
        uint[] memory amounts = i_router.getAmountsOut(amountIn, path);
        return amounts[1];
    }

}