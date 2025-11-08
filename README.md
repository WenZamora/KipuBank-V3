# KipuBank-V3

## Descripción
**KipuBankV3** es la evolución del contrato  `KipuBankV2`.
Su objetivo es simplificar la experiencia del usuario al aceptar **cualquier token ERC20** y gestionar la complejidad de la conversión interna. Esto permite a los usuarios depositar diversos activos, mientras que el banco mantiene una **contabilidad estable y unificada** en USDC, optimizando la gestión de liquidez y respetando los límites de capital.
Mantiene la robustez de las versiones anteriores, utilizando librerías de OpenZeppelin (`Ownable`, `ReentrancyGuard`) para asegurar el control de acceso y la protección de los fondos del protocolo.

---

## Mejoras Implementadas

Las mejoras en esta versión se centran en la integración de protocolos para lograr una contabilidad estable más eficiente y robusta, eliminando la dependencia de oráculos externos para cada token depositado.

1. **Integración de Protocolos: Uniswap V2**
  - *Swap Automático a USDC*: La función depositar ahora acepta cualquier token ERC20 (que tenga un par de Uniswap con USDC/WETH) y ejecuta automáticamente un swap a USDC a través del Router de Uniswap V2.
  - *Contabilidad Unificada*: Toda la liquidez depositada se convierte y se registra internamente en USDC (`s_depositosUSDC`), simplificando la contabilidad del banco.
  - *Eliminación de Oráculos*: Se ha removido la dependencia de Chainlink para la conversión de precios durante el depósito, ya que el swap de Uniswap proporciona el precio de mercado final en USDC.

2. **Contabilidad y Gestión de Riesgos**
   - *Límites Post-Swap*: El sistema garantiza el respeto estricto del bankCap (`i_bankCapUSD`) y el maxRetiroUSD (`i_maxRetiroUSD`) al validar el valor en USDC después de que se ejecuta el swap. Esto asegura   que el valor de la liquidez convertida no exceda el límite del banco.
  - *Inmutabilidad*: Se mantiene el uso de variables immutable para los parámetros críticos de riesgo (`bankCap`, `maxRetiro`) y las direcciones de protocolos (`i_router`, `i_USDC`).

3. **Seguridad y Gestión de Riesgos**
  - *nonReentrant*: Se mantiene el estricto uso del modificador nonReentrant de OpenZeppelin en las funciones críticas para evitar ataques de reentrada, protegiendo los fondos durante y después de la interacción con Uniswap.
  - *Seguridad en Tokens (SafeERC20)*: Se conserva el uso de SafeERC20 para todas las interacciones de tokens (aprobaciones y transferencias) con el Router de Uniswap, previniendo edge cases maliciosos.
  - *Control de Acceso*: Se mantiene el uso de Ownable para restringir funciones administrativas al propietario.
  - *Doble Verificación de Límites (Pre-Swap)*: El sistema realiza una estimación del monto de USDC esperado antes de ejecutar el swap para revertir la transacción (KipuBank_ExcedeLimiteGlobal) de forma temprana y ahorrar gas si el depósito supera el límite global del banco.
  - Protección de Allowance (SafeERC20): Se utiliza el patrón safeIncreaseAllowance para manejar la aprobación de tokens al Router de Uniswap V2. Esto previene el ataque de carrera de aprobación (race condition), un riesgo conocido al interactuar con el allowance de tokens ERC-20.

---

## Instrucciones de Despliegue

1. Abrir Remix IDE (https://remix.ethereum.org/) (o el entorno de desarrollo de su preferencia).
2. Crear un archivo `KipuBankV3.sol` dentro de la carpeta `contracts/` en la pestaña `File explorer` y copiar el código del contrato.
3. En la pestaña `Solidity compiler`, seleccionar la **versión del compilador** `0.8.30` y compilar el contrato.
4. Ir a la pestaña **Deploy & Run Transactions** y configurar:
   - **Environment:** Injected Web3 (para usar MetaMask u otra billetera)
   - **Account:** la cuenta de la testnet Sepolia (u otra testnet configurada en MetaMask).
   - **Contract:** Asegurarse de que esté seleccionado este contrato `KipuBankV3` 
    - **Constructor Arguments:** establecer los valores de los parámetros del constructor, por ejemplo: ```1000, 1000000,0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3,0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238```
5. Hacer clic en **Deploy** y confirmar la transacción en MetaMask..

Una vez confirmada la transaccion, el contrato quedará desplegado en la testnet.

---

## Interacción con el Contrato

Una vez desplegado el contrato, se puede interactuar desde la pestaña `Deploy & run transactions` en Remix.

**Depositar fondos**
Recibe tokens (o ETH), realiza el swap a USDC a través del Router y acredita el saldo al usuario.
- Debe ingresar la direccion del token a depositar y cantidad del token/ETH a depositar.
  Valores de ejemplo: 0x0000000000000000000000000000000000000000, 1000000000000000000
- Hacer clic en **depositar**.
- Si es ERC-20:** Requiere **`approve()`** previo del usuario.

**Retirar fondos**
Permite al usuario retirar su saldo en USDC.
- Debe ingresar la direccion de USDC y la cantidad a retirar
   Valores de ejemplo: 0x0000000000000000000000000000000000000000, 200000000000000000000
- Hacer clic en **retirar**.
- Si no se ingre la direccion USDC, revierte con KipuBank_TokenNoSoportado.
- El contrato validará que el saldo del token y el límite en USD no sean superados antes de ejecutar la transferencia.

**verTotalDepositosUSDC**
Muestra el total global de todos los USDC depositados en el Banco.
- Hacer clic en **verTotalDepositosUSD** (No requiere que se ingresen valor de argumentos)
- Muestra el total de activos del banco, valorado en USDC.

**verFondoUSDC**
Muestra el saldo total en USDC que un usuario tiene depositado.
- Debe ingresar la direccion a consultar.
- Hacer clic en **verFondo**
- Muestra el saldo del usuario en USDC.

**verLimiteRetiroUSDC**
Muestra el límite máximo que se puede retirar en una sola transacción.
- Hacer clic en **verLimiteRetiroUSD**
- Muestra el límite en USDC

---

## Decisiones de Diseño 
* **Trade-off: Modificadores vs. CEI:**
Todas las validaciones de límites, nonReentrant y lógica de saldo se ejecuta explícitamente dentro del cuerpo de la función (depositar, retirar), siguiendo estrictamente el patrón CEI para garantizar que los effects (actualización de saldos) se hagan antes de las interactions (el swap o la transferencia de retiro).
* **Unificación ETH/ERC20:** Se mantiene el uso de address(0) (ETH_ADDRESS) para el flujo de depósito de Ether. Ahora, esta unificación dirige el flujo a las funciones específicas de Uniswap: swapExactETHForTokens (para ETH) y swapExactTokensForTokens (para ERC-20).
*  **Control de Slippage (Deslizamiento):** Se decidió calcular y exigir un monto mínimo de USDC (minOut) en las llamadas al swap. Esto previene pérdidas significativas si la liquidez cambia drásticamente entre el momento en que se firma la transacción y el momento en que se ejecuta en la blockchain.
*  **Protección Contra Pérdida de Gas (Doble Check de Límite) :**Se optó por incluir una estimación previa al swap (getAmountsOut) para verificar si el depósito excede el i_bankCapUSD. Si el límite se va a superar, la transacción revierte antes de ejecutar el swap en Uniswap, ahorrando gas al usuario y al banco.
*  **Patrón de Aprobación Segura (Safe Allowance) :**Se decidió implementar el patrón safeIncreaseAllowance en lugar del approve simple al interactuar con el Router. Esto mitiga el riesgo de ataque de carrera de aprobación (race condition) al dar permisos al Router de Uniswap para gastar los tokens depositados.
*  **Transferencia Segura y Reentrancy Guard (Retiro) :**Se decidió depender completamente de ReentrancyGuard y SafeERC20.safeTransfer en la función retirar. Esta combinación es la protección estándar de la industria para prevenir ataques de reentrada mientras se manejan transferencias de tokens.
  
---
